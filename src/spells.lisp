(in-package #:hexmaw)

;;; Daggerfall-style spells. A spell is a delivery (how it reaches its target)
;;; plus a list of effects. Each effect has a kind, a magnitude range, a duration,
;;; an area, a target type and, for damage, an element, and the spell's cost is derived
;;; from that composition, so the spellforge (forge.lisp) builds new spells from the same
;;; parts. What an effect kind does is a method on APPLY-EFFECT (here, and in magic.lisp
;;; for statuses, elements, healing and the rest).

(defclass effect ()
  ((kind :initarg :kind :reader effect-kind
         :documentation "Keyword naming what the effect does: :DAMAGE, :KNOCKBACK, ...")
   (magnitude :initarg :magnitude :initform '(1 1) :reader effect-magnitude
              :documentation "(MIN MAX); each application rolls an integer in that range.")
   (duration :initarg :duration :initform 0 :reader effect-duration
             :documentation "Seconds; 0 is instant. An over-time kind's magnitude is then per
second (damage, heal), a status kind's what it holds for that long (*EFFECT-KINDS*).")
   (area :initarg :area :initform 0 :reader effect-area
         :documentation "Radius in metres; 0 is a single target. A :CIRCLE delivery's reach,
otherwise a burst where the spell strikes.")
   (target-type :initarg :target-type :initform :target :reader effect-target-type
                :documentation ":SELF (the caster) or :TARGET (whatever the delivery hits;
:TOUCH means the same).")
   (element :initarg :element :initform NIL :reader effect-element
            :documentation "A damage effect's element, :FIRE, :FROST or :SHOCK, or NIL.")))

(defclass spell ()
  ((name :initarg :name :reader spell-name)
   (delivery :initarg :delivery :initform :projectile :reader spell-delivery)
   (projectile-speed :initarg :projectile-speed :initform 20.0 :reader projectile-speed)
   (projectile-animation :initarg :projectile-animation :initform NIL :reader projectile-animation
                         :documentation "Effect animation the projectile flies as.")
   (impact-animation :initarg :impact-animation :initform NIL :reader impact-animation
                     :documentation "Effect animation played where the projectile hits, or NIL.")
   (light-color :initarg :light-color :initform *bolt-light-color* :reader light-color
                :documentation "Colour of the glow the projectile and its impact cast.")
   (light-radius :initarg :light-radius :initform *bolt-light-radius* :reader light-radius)
   (homing :initarg :homing :initform NIL :reader spell-homing
           :documentation "Radians a second a creature's projectile turns after the player; NIL flies straight.")
   (pain-bonus :initarg :pain-bonus :initform 0 :reader spell-pain-bonus
               :documentation "Percent its damage adds to a creature's PAIN-CHANCE.")
   (lifetime :initarg :lifetime :initform NIL :reader spell-lifetime
             :documentation "Seconds a projectile that hit nothing flies; NIL for *PROJECTILE-LIFETIME*.")
   (windup :initarg :windup :initform 2.5 :reader spell-windup
           :documentation "Seconds a :CIRCLE delivery glows on the floor before it strikes.")
   (circle-animation :initarg :circle-animation :initform NIL :reader circle-animation
                     :documentation "A :CIRCLE's sign on the floor: frames drawing it in, then a pulsing loop of 4.")

   (strike-animation :initarg :strike-animation :initform NIL :reader strike-animation
                     :documentation "What bursts up out of a :CIRCLE's floor when it strikes, played many times over it.")
   (effects :initarg :effects :reader spell-effects)))

(defvar *spells* (make-hash-table :test 'eq))

(defun find-spell (name)
  (or (gethash name *spells*) (error "No spell named ~s." name)))

(defun spell-title (spell)
  "SPELL's name as the player reads it: a forged spell's own, or a defined one's symbol."
  (let ((name (spell-name spell)))
    (if (stringp name) name (substitute #\Space #\- (string-capitalize name)))))

(defmacro define-spell (name (&rest options) &body effects)
  "Define spell NAME. OPTIONS are SPELL initargs; each effect is (KIND &rest EFFECT-INITARGS):

  (define-spell bolt (:delivery :projectile :projectile-speed 20.0)
    (:damage :magnitude '(6 10))
    (:knockback :magnitude '(4 4)))"
  `(setf (gethash ',name *spells*)
         (make-instance 'spell :name ',name ,@options
                               :effects (list ,@(loop for (kind . args) in effects
                                                      collect `(make-instance 'effect :kind ,kind ,@args))))))

;;; Cost: each effect's base cost times its average magnitude, scaled by how long it
;;; lasts and by its area; a touch spell is cheaper, since it costs the caster a step
;;; into reach. A spell costs the sum, rounded up.

(defparameter *effect-kinds*
  '((:damage :base 1.5 :timing :over-time :targets (:target) :magnitude 30 :duration 8 :area 3.0)
    (:heal :base 1.0 :timing :over-time :targets (:self) :magnitude 40 :duration 10 :area 0)
    (:knockback :base 0.5 :timing :instant :targets (:target) :magnitude 12 :duration 0 :area 3.0)
    (:slow :base 0.12 :timing :status :targets (:target) :magnitude 60 :duration 10 :area 3.0)
    (:drain :base 2.0 :timing :instant :targets (:target) :magnitude 20 :duration 0 :area 0)
    (:ward :base 0.4 :timing :status :targets (:self) :magnitude 40 :duration 20 :area 0))
  "What each effect kind the spellforge offers is: mana per point of average magnitude
(:BASE), how its duration counts (:TIMING: :INSTANT ignores it, :OVER-TIME makes the
magnitude per second, :STATUS holds the magnitude that long), who it may strike
(:TARGETS), and the most magnitude, duration and area the forge allows. Kinds not
listed (creatures' :WHIRL, :GUST) cost 1 a point, their duration counting as a status's.")

(defparameter *element-costs* '(:fire 1.5 :frost 1.7 :shock 1.7)
  "Mana per point of damage, by element: frost and shock do more than fire.")
(defparameter *over-time-discount* 0.6
  "An over-time effect costs its magnitude a second times its duration times this.")
(defparameter *touch-cost-scale* 0.75 "A :TOUCH spell's cost, against the same at range.")

(defun kind-property (kind property &optional default)
  (getf (rest (assoc kind *effect-kinds*)) property default))

(defun effect-cost (effect &optional delivery)
  (destructuring-bind (lo hi) (effect-magnitude effect)
    (let* ((kind (effect-kind effect))
           (duration (effect-duration effect))
           (base (or (and (eq kind :damage) (getf *element-costs* (effect-element effect)))
                     (kind-property kind :base 1.0)))
           (time (ecase (kind-property kind :timing :status)
                   (:instant 1)
                   (:over-time (if (< 0 duration) (* duration *over-time-discount*) 1))
                   (:status (+ 1 (/ duration 5))))))
      (* base (/ (+ lo hi) 2) time
         (+ 1 (effect-area effect))
         (if (eq delivery :touch) *touch-cost-scale* 1)))))

(defun spell-cost (spell)
  (ceiling (reduce #'+ (spell-effects spell)
                   :key (lambda (effect) (effect-cost effect (spell-delivery spell))))))

(defun roll (magnitude)
  (destructuring-bind (lo hi) magnitude
    (+ lo (random (1+ (- hi lo)) *roll-random*))))

;;; Effects.

(defgeneric apply-effect (kind effect target source)
  (:documentation "Apply EFFECT, whose kind is KIND, to TARGET. SOURCE is what delivered
it (a SPELL-PROJECTILE for projectile spells, a SPELL-CIRCLE for circles)."))

(defmethod apply-effect (kind effect target source)
  (v:warn :hexmaw "No ~s effect for ~a; ignored." kind target))

(defgeneric effect-origin (source)
  (:documentation "The point an effect delivered by SOURCE strikes from, or NIL.")
  (:method (source) NIL))

(defgeneric effect-direction (source target)
  (:documentation "The way an effect delivered by SOURCE pushes TARGET, a vector whose
horizontal part counts."))

(defgeneric effect-unblockable-p (source)
  (:documentation "True if the player's raised shield does nothing against an effect
delivered by SOURCE.")
  (:method (source) NIL))

(defmethod apply-effect ((kind (eql :knockback)) effect (target creature) source)
  (push-creature target (effect-direction source target) (float (roll (effect-magnitude effect)) 0f0)))

(defun target-effect-p (effect)
  (member (effect-target-type effect) '(:target :touch)))

(defun apply-spell (spell target source)
  "Apply SPELL's effects on what it reaches to TARGET, whatever their area (a circle's)."
  (dolist (effect (spell-effects spell))
    (when (target-effect-p effect)
      (apply-effect (effect-kind effect) effect target source))))

(defun apply-self-effects (spell caster source)
  (dolist (effect (spell-effects spell))
    (when (eq :self (effect-target-type effect))
      (apply-effect (effect-kind effect) effect caster source))))

;;; Striking: a projectile or a touch reaches a point, hitting a body there or nothing (a
;;; wall). Its single-target effects strike that body; an effect with an area bursts over
;;; every body within it that the point can see, but its caster and those it spares.

(defclass strike ()
  ((spell :initarg :spell :reader spell)
   (caster :initarg :caster :initform NIL :reader caster)
   (origin :initarg :origin :reader strike-origin
           :documentation "Where it strikes from: what it pushes away from."))
  (:documentation "The source of effects that land without a projectile in flight: a burst,
a touch, a weapon's enchantment."))

(defmethod effect-origin ((source strike))
  (strike-origin source))

(defmethod effect-direction ((source strike) target)
  (v- (if (typep target 'player) (feet target) (location target)) (strike-origin source)))

(defun burst-spell (spell point caster)
  "Burst SPELL's effects that have an area over every body within it of POINT."
  (dolist (effect (spell-effects spell))
    (when (and (target-effect-p effect) (< 0 (effect-area effect)))
      (let ((burst (make-instance 'strike :spell spell :caster caster :origin point)))
        (dolist (body (burst-victims point (effect-area effect) caster))
          (apply-effect (effect-kind effect) effect body burst))))))

(defun strike-with-spell (spell victim origin caster &optional (at origin))
  "SPELL, cast by CASTER, strikes without a projectile (a touch, an enchanted blow): its
single-target effects strike VICTIM (or no one) from point ORIGIN, those with an area
burst over every body within it of point AT."
  (when victim
    (let ((source (make-instance 'strike :spell spell :caster caster :origin origin)))
      (dolist (effect (spell-effects spell))
        (when (and (target-effect-p effect) (= 0 (effect-area effect)))
          (apply-effect (effect-kind effect) effect victim source)))))
  (burst-spell spell at caster))

(defun spell-burst-radius (spell)
  "The widest area of SPELL's effects on what it strikes, 0 for none."
  (loop for effect in (spell-effects spell)
        when (target-effect-p effect) maximize (effect-area effect)))

;;; Projectile delivery.

(defparameter *projectile-lifetime* 3.0 "Seconds before a projectile that hit nothing vanishes.")
(defparameter *projectile-size* 0.18 "Collision diameter in metres; the sprite can be bigger.")
(defparameter *impact-pullback* 0.25
  "Metres back along the flight path where the impact plays, so it isn't buried in the wall.")

(define-shader-entity spell-projectile (fx-sprite)
  ((spell :initarg :spell :initform NIL :reader spell)
   (caster :initarg :caster :initform NIL :accessor caster
           :documentation "Who fired it (the player or a creature), whom it never hits.")
   (homing :initarg :homing :initform NIL :accessor homing
           :documentation "Radians a second it turns after the player, or NIL; a shield that
turns it aside ends it.")
   (projectile-velocity :initform (vec 0 0 0) :reader projectile-velocity)
   (submerged :initform NIL :accessor submerged
              :documentation "True while it is in a liquid: one cast under water flies on in it,
and bursts only on entering one from outside.")
   (evade-asked :initform NIL :accessor evade-asked
                :documentation "The creature last asked whether it evades this (the player's)
projectile about to reach it, so each is asked once.")
   (sound :initform NIL :accessor projectile-sound
          :documentation "Its flight's loop (sound.lisp), from its first tick until it leaves.")))

(defparameter *spell-sounds*
  '(bolt (:flight :bolt-flight :impact :bolt-impact)
    cinder (:flight :cinder-flight :impact :cinder-impact)
    grave-skull (:cast :skull-cast :flight :skull-flight :impact :skull-impact)
    grave-spikes (:circle :grave-circle :strike :grave-spikes)
    gust (:cast :gust-cast)
    rift-pull (:cast :rift-cast :flight :rift-flight :impact :rift-impact)
    rift-swap (:cast :rift-cast :flight :rift-flight :impact :rift-impact)
    rift-push (:cast :rift-cast :flight :rift-flight :impact :rift-impact))
  "Each spell's clips (sound.lisp) by event: :CAST where a creature lets it go, :FLIGHT its
projectile's loop, :IMPACT its burst, :CIRCLE a circle's loop through its wind-up and :STRIKE
its strike. The player's own casts sound from the hands (player.lisp).")

(defun spell-sound (spell event)
  ;; A forged spell (named by a string, SPEC-SPELL) sounds like the bolt.
  (getf (getf *spell-sounds* (if (stringp (spell-name spell)) 'bolt (spell-name spell))) event))

;; A reset, a rebuild or its end takes it away: its flight falls silent.
(defmethod leave :after ((projectile spell-projectile) container)
  (setf (projectile-sound projectile) (stop-loop (projectile-sound projectile))))

;; It strikes from behind itself, along its flight, and pushes along it.
(defmethod effect-origin ((source spell-projectile))
  (v- (location source) (projectile-velocity source)))

(defmethod effect-direction ((source spell-projectile) target)
  (projectile-velocity source))

(defun launch-projectile (spell origin direction container caster)
  "Fire SPELL from ORIGIN along unit vector DIRECTION, on behalf of CASTER."
  (let ((projectile (make-instance 'spell-projectile
                                  :spell spell :caster caster :location (vcopy origin)
                                  :homing (spell-homing spell)
                                  :animation (find-fx-animation (projectile-animation spell)))))
    (v<- (projectile-velocity projectile) direction)
    (setf (submerged projectile) (and (liquid-at (vx origin) (vy origin) (vz origin)) T))
    (nv* (projectile-velocity projectile) (float (projectile-speed spell) 0f0))
    (enter projectile container)
    (attach-glow projectile (light-color spell) (light-radius spell))
    projectile))

(defparameter *burst-size* 0.45
  "Radius in metres an impact animation's burst stands for: one bursting over an area is
drawn that much bigger.")

(defun impact-point (projectile)
  "Where PROJECTILE's impact plays: a little back along its flight, out of the wall."
  (let ((velocity (projectile-velocity projectile)))
    (v- (location projectile) (v* velocity (/ *impact-pullback* (max 0.001 (vlength velocity)))))))

(defun play-impact (spell at container &key water)
  "Play SPELL's impact animation at AT, as big as its burst, with its glow and its sound. Into
WATER it hisses out."
  (let ((name (impact-animation spell)))
    (when (and name container)
      (let ((sprite (spawn-fx name at container))
            (k (max 1.0 (/ (spell-burst-radius spell) *burst-size*))))
        (nv* (scaling sprite) k)
        (attach-glow sprite (light-color spell) (* (light-radius spell) (sqrt k)))
        (play-sound (if water :bolt-hiss-water (spell-sound spell :impact)) at)))))

(defun impact (projectile &key water (at (impact-point projectile)))
  "Play the spell's impact where PROJECTILE hit, and remove it. Into WATER it hisses out."
  (play-impact (spell projectile) at (container projectile) :water water)
  (despawn projectile))

;; The player's own projectiles never hit them, nor a creature's that creature.
(defun projectile-victim (projectile point margin)
  "The body PROJECTILE hits at POINT, MARGIN metres around it: a live creature or the player."
  (let ((caster (caster projectile)))
    (or (creature-at point margin caster)
        (and *player* (not (eq caster *player*)) (player-at-p *player* point margin)
             *player*))))

;;; Shields. A spell striking a shield from the front (SHIELDED-P, creature.lisp: the
;;; views of the sprite its shield covers) does nothing to the bearer. A shield that
;;; reflects sends it back the way it came, mirrored off the shield's face, as the
;;; bearer's own; one that doesn't, stops it.

(defgeneric deflects-p (target projectile)
  (:documentation "True if TARGET turns PROJECTILE aside instead of taking its effects.")
  (:method (target projectile) NIL))

(defmethod deflects-p ((target creature) (projectile spell-projectile))
  (shielded-p target (v- (location target) (projectile-velocity projectile))))

(defun deflect (target projectile)
  "TARGET's shield takes PROJECTILE: reflect it, or stop it if the shield doesn't reflect."
  (block-hit target)
  (play-sound :shield-deflect (location projectile))
  (cond ((shield-reflects target)
         ;; Mirror the flight off the shield's face, whose normal is the way TARGET faces,
         ;; and send it back up or down too: straight on, it returns to its caster.
         (let* ((v (projectile-velocity projectile))
                (nx (sin (facing target)))
                (nz (- (cos (facing target))))
                (d (+ (* (vx v) nx) (* (vz v) nz))))
           (setf (vx v) (- (vx v) (* 2 d nx))
                 (vz v) (- (vz v) (* 2 d nz))
                 (vy v) (- (vy v))))
         (setf (caster projectile) target
               (homing projectile) NIL
               (age projectile) 0.0))
        (T
         (impact projectile))))

(defun steer (projectile dt)
  "Turn PROJECTILE's flight toward the player's chest by at most its HOMING rate for DT
seconds, keeping its speed."
  (let* ((v (projectile-velocity projectile))
         (loc (location projectile))
         (feet (feet *player*))
         (tx (- (vx feet) (vx loc)))
         (ty (- (+ (vy feet) *cast-aim-height*) (vy loc)))
         (tz (- (vz feet) (vz loc)))
         (tl (sqrt (+ (* tx tx) (* ty ty) (* tz tz))))
         (speed (vlength v)))
    (when (and (< 1f-3 tl) (< 1f-3 speed))
      (let* ((ux (/ (vx v) speed)) (uy (/ (vy v) speed)) (uz (/ (vz v) speed))
             (dx (/ tx tl)) (dy (/ ty tl)) (dz (/ tz tl))
             (cos-a (max -1f0 (min 1f0 (+ (* ux dx) (* uy dy) (* uz dz)))))
             (step (* (homing projectile) dt)))
        (if (<= (acos cos-a) step)
            (setf (vx v) (* speed dx) (vy v) (* speed dy) (vz v) (* speed dz))
            ;; Rotate toward the target in the plane of the flight and the target: W is the
            ;; part of the way to the target square to the flight.
            (let* ((wx (- dx (* cos-a ux))) (wy (- dy (* cos-a uy))) (wz (- dz (* cos-a uz)))
                   (wl (sqrt (+ (* wx wx) (* wy wy) (* wz wz)))))
              (when (< 1f-5 wl)
                (let ((c (cos step)) (s (/ (sin step) wl)))
                  (setf (vx v) (* speed (+ (* c ux) (* s wx)))
                        (vy v) (* speed (+ (* c uy) (* s wy)))
                        (vz v) (* speed (+ (* c uz) (* s wz))))))))))))

(defparameter *evade-look-ahead* 0.2
  "Seconds of flight ahead of the player's projectile that a creature sees it coming (EVADE-PROJECTILE).")

(defgeneric evade-projectile (creature projectile)
  (:documentation "Give CREATURE, which the player's PROJECTILE is about to reach, its chance
to get out of the way (the riftwalker's blink, riftwalker.lisp). Asked once per projectile.")
  (:method (creature projectile) NIL))

(defvar *evade-probe* (vec 0 0 0))

(defun look-ahead (projectile r)
  "Ask the creature the player's PROJECTILE will reach within *EVADE-LOOK-AHEAD* whether it evades it."
  (let ((probe *evade-probe*)
        (loc (location projectile))
        (v (projectile-velocity projectile))
        (k (float *evade-look-ahead* 0f0)))
    (setf (vx probe) (+ (vx loc) (* k (vx v)))
          (vy probe) (+ (vy loc) (* k (vy v)))
          (vz probe) (+ (vz loc) (* k (vz v))))
    (let ((c (creature-at probe r *player*)))
      (when (and c (not (eq c (evade-asked projectile))))
        (setf (evade-asked projectile) c)
        (evade-projectile c projectile)))))

;; After FX-SPRITE's tick, which animates and ages it.
(define-handler (spell-projectile tick :after) (dt)
  (unless (frozen-p)
    (let* ((loc (location spell-projectile))
           (r (* 0.5 (float *projectile-size* 0f0))))
      (when (and (homing spell-projectile) *player* (not (eq (caster spell-projectile) *player*)))
        (steer spell-projectile (float dt 0f0)))
      (when (and *player* (eq (caster spell-projectile) *player*))
        (look-ahead spell-projectile r))
      (nv+* loc (projectile-velocity spell-projectile) dt)
      (let ((sound (projectile-sound spell-projectile)))
        (if sound
            (move-loop sound loc)
            (setf (projectile-sound spell-projectile)
                  (start-loop (spell-sound (spell spell-projectile) :flight) loc))))
      (let ((victim (projectile-victim spell-projectile loc r))
            (entered (and (not (submerged spell-projectile)) (liquid-at (vx loc) (vy loc) (vz loc)))))
        (setf (submerged spell-projectile) (and (liquid-at (vx loc) (vy loc) (vz loc)) T))
        (cond ((and victim (deflects-p victim spell-projectile))
               (deflect victim spell-projectile))
              (victim
               ;; Its own effects strike from along its flight; a burst from where it hit.
               (dolist (effect (spell-effects (spell spell-projectile)))
                 (when (and (target-effect-p effect) (= 0 (effect-area effect)))
                   (apply-effect (effect-kind effect) effect victim spell-projectile)))
               (let ((at (impact-point spell-projectile)))
                 (burst-spell (spell spell-projectile) at (caster spell-projectile))
                 (impact spell-projectile :at at)))
              ((or entered (solid-overlapping (vx loc) (- (vy loc) r) (vz loc) r (* 2 r)))
               (let ((at (impact-point spell-projectile)))
                 (burst-spell (spell spell-projectile) at (caster spell-projectile))
                 (impact spell-projectile :at at
                                          :water (and entered (liquid-property (liquid-kind entered) :swim)))))
              ((< (or (spell-lifetime (spell spell-projectile)) *projectile-lifetime*) (age spell-projectile))
               (despawn spell-projectile)))))))

;;; Circle delivery: a sign glows on the floor around a point for the spell's WINDUP,
;;; an aurora rising round it and a lamp brightening over it, so it shows from
;;; anywhere in the room; then it strikes everything living that stands in it, once
;;; (the effects' AREA is its radius), and its STRIKE-ANIMATION bursts up all over it.
;;; Once cast it goes on by itself: hitting or killing its caster doesn't stop it. Nor
;;; does it spare the caster's allies, only the caster and the undead.

(defparameter *aurora-height* '(0.3 3.2) "Metres a circle's aurora rises from and to as it winds up.")
(defparameter *aurora-segments* 128 "Quads round an aurora's ring. Read when the ring is made (a restart).")
(defparameter *circle-draw-in* 0.45 "Fraction of the wind-up a circle's sign takes to draw itself.")
(defparameter *circle-pulse-fps* 8.0)
(defparameter *circle-light-color* (vec 0.5 2.2 0.6) "Its lamp's colour at full strength, just before it strikes.")
(defparameter *circle-light-radius* 7.0)
(defparameter *circle-flash* 2.0 "How much brighter the lamp flashes as the circle strikes.")
(defparameter *circle-linger* 0.8 "Seconds the sign and its light fade after the strike.")
(defparameter *circle-reach-height* 1.0 "Metres above or below the sign that feet can be to be struck.")
(defparameter *strike-rings* '((0.0 1) (0.5 4) (0.9 6))
  "Where the strike bursts up: (FRACTION-OF-RADIUS COUNT) rings, from the middle out.")
(defparameter *strike-ring-delay* 0.06 "Seconds between one ring of the strike and the next.")
(defparameter *harvest-blood* 30 "Drops the strike wrenches up out of each living thing it hits.")

(define-shader-entity upright-fx (fx-sprite) ()
  (:documentation "An effect sprite turned only about +Y, standing upright as a billboard does."))

(define-handler (upright-fx tick :after) ()
  (let ((camera (camera (scene +main+))))
    (when (typep camera 'fps-camera)
      (!qfrom-angle (orientation upright-fx) +vy+ (- (vy (rotation camera)))))))

(defun spawn-standing-fx (name x y z container &key (class 'upright-fx))
  "Play effect animation NAME once, upright, standing on the floor at X Y Z."
  (let* ((animation (find-fx-animation name))
         (sprite (make-instance class :animation animation
                                      :location (vec x (+ y (* 0.5 (animation-size animation))) z))))
    (enter sprite container)
    sprite))

;;; The aurora: a curtain of light standing on a circle's rim like the northern lights:
;;; soft vertical streaks of many heights, drifting and shimmering along it, a bright band
;;; along its foot, its colour wandering through the necromancer's greens round the ring
;;; and deepening toward the top. It is a ring of quads whose vertices are
;;; an angle round the ring and a height up it; the shader sways the upper part (the foot
;;; stays on the rim) and adds its light over what is behind it, writing no depth, so it
;;; needs no sorting against other glows. COLORS gives it another caster's look, and
;;; SPIN and TWIST make its streaks a wind's, running round it and leaning.

(defparameter *grave-aurora-colors*
  (list (vec 0.1 1.0 0.35) (vec 0.5 1.0 0.15) (vec 0.15 0.95 0.65) (vec 0.05 0.55 0.25) (vec 0.8 1.0 0.7))
  "An aurora's colours: the three its foot wanders through round the ring, its top, its band.")

(define-shader-entity aurora (renderable listener)
  ((centre :initarg :centre :reader centre)
   (radius :initarg :radius :reader aurora-radius)
   (colors :initarg :colors :initform *grave-aurora-colors* :reader aurora-colors)
   (spin :initarg :spin :initform 0.0 :reader aurora-spin :documentation "Turns a second its streaks run round the ring.")
   (twist :initarg :twist :initform 0.0 :reader aurora-twist :documentation "Whole turns its streaks lean, foot to top.")
   (arc :initarg :arc :initform pi :accessor aurora-arc
        :documentation "Radians either side of ARC-MIDDLE it stands on: pi for the whole ring, less for an arc.")
   (arc-middle :initarg :arc-middle :initform pi :accessor aurora-arc-middle
               :documentation "Angle round the ring, from +X toward +Z, of its arc's middle.")
   (height :initform (first *aurora-height*) :accessor aurora-height)
   (strength :initform 0.0 :accessor aurora-strength :documentation "0 (none) to 1 (full).")
   (clock :initform (random 100.0) :accessor aurora-clock)))

(defvar *aurora-vao* NIL
  "The ring every aurora draws, shared: one made mid-game would never be loaded onto the
GPU. PRELOAD-SPELLS stages it with the scene.")

(defun aurora-vao ()
  (or *aurora-vao*
      (let* ((n *aurora-segments*)
             (data (make-array (* n 12) :element-type 'single-float))
             (k 0))
        ;; Two triangles a segment, each vertex (fraction of the way round, fraction up).
        (dotimes (i n)
          (let ((a0 (float (/ i n) 0f0)) (a1 (float (/ (1+ i) n) 0f0)))
            (loop for v in (list a0 0f0 a1 0f0 a1 1f0 a0 0f0 a1 1f0 a0 1f0)
                  do (setf (aref data k) v) (incf k))))
        (setf *aurora-vao*
              (make-instance 'vertex-array
                             :vertex-form :triangles
                             :bindings `((,(make-instance 'vertex-buffer :buffer-data data) :size 2 :offset 0 :stride 8 :index 0))
                             :size (* n 6))))))

(defmethod stage :after ((aurora aurora) (area staging-area))
  (stage (aurora-vao) area))

(define-handler (aurora tick) (dt)
  (unless (frozen-p)
    (incf (aurora-clock aurora) dt)))

(defmethod render ((aurora aurora) (program shader-program))
  (when (< 0 (aurora-strength aurora))
    (setf (uniform program "view_matrix") (view-matrix)
          (uniform program "projection_matrix") (projection-matrix)
          (uniform program "centre") (centre aurora)
          (uniform program "radius") (float (aurora-radius aurora) 0f0)
          (uniform program "height") (float (aurora-height aurora) 0f0)
          (uniform program "strength") (float (aurora-strength aurora) 0f0)
          (uniform program "spin") (float (aurora-spin aurora) 0f0)
          (uniform program "twist") (float (aurora-twist aurora) 0f0)
          (uniform program "arc") (float (aurora-arc aurora) 0f0)
          (uniform program "arc_middle") (float (aurora-arc-middle aurora) 0f0)
          (uniform program "time") (float (aurora-clock aurora) 0f0))
    (destructuring-bind (foot-1 foot-2 foot-3 top band) (aurora-colors aurora)
      (setf (uniform program "foot_1") foot-1
            (uniform program "foot_2") foot-2
            (uniform program "foot_3") foot-3
            (uniform program "top_color") top
            (uniform program "band_color") band))
    ;; Light added over what is behind it, seen from outside the ring and from inside.
    (gl:disable :cull-face)
    (gl:depth-mask NIL)
    (gl:blend-func :one :one)
    (render-array (aurora-vao))
    (gl:blend-func :src-alpha :one-minus-src-alpha)
    (gl:depth-mask T)
    (gl:enable :cull-face)))

(define-class-shader (aurora :vertex-shader)
  "layout (location = 0) in vec2 in_ah;
uniform mat4 view_matrix;
uniform mat4 projection_matrix;
uniform vec3 centre;
uniform float radius;
uniform float height;
uniform float time;
uniform float arc;
uniform float arc_middle;
out vec2 v_ah;

void main(){
  // The ring's segments spread over its arc: the whole ring when ARC is pi.
  float a = arc_middle + (in_ah.x - 0.5) * 2.0 * arc;
  // Folds that drift round the ring and sway, growing toward the top: the foot stays
  // on the circle's rim.
  float lean = in_ah.y * in_ah.y;
  float fold = 0.08 * sin(5.0 * a + time * 0.9) + 0.04 * sin(12.0 * a - time * 1.6)
             + 0.08 * sin(3.0 * a + time * 0.7);
  float r = radius * (1.0 + lean * fold);
  vec3 p = centre + vec3(cos(a) * r, in_ah.y * height, sin(a) * r);
  gl_Position = projection_matrix * (view_matrix * vec4(p, 1.0));
  v_ah = in_ah;
}")

(define-class-shader (aurora :fragment-shader)
  "in vec2 v_ah;
uniform float strength;
uniform float spin;
uniform float twist;
uniform float time;
uniform float arc;
uniform vec3 foot_1;
uniform vec3 foot_2;
uniform vec3 foot_3;
uniform vec3 top_color;
uniform vec3 band_color;
out vec4 color;

float hash(float n){ return fract(sin(n * 127.1) * 43758.5453); }

// Smooth noise along the ring, repeating every PERIOD cells, so it meets itself.
float ring_noise(float x, float period){
  float i = floor(x);
  float f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(hash(mod(i, period)), hash(mod(i + 1.0, period)), f);
}

void main(){
  float y = v_ah.y;
  float u = v_ah.x + fract(spin * time) + twist * y;
  // Streaks: a broad set and a fine one, sharpened into separate rays, drifting.
  float broad = ring_noise(u * 70.0 + time * 0.8, 70.0);
  float fine = ring_noise(u * 190.0 - time * 1.9, 190.0);
  float streak = 0.75 * pow(broad, 2.5) + 0.6 * pow(fine, 4.0);
  // Each ray has its own height, the tallest the whole curtain, and they rise and fall.
  float top = 0.25 + 0.75 * ring_noise(u * 40.0 + 7.0 + time * 0.35, 40.0);
  float rise = smoothstep(0.0, 0.03, y) * (1.0 - smoothstep(top * 0.3, top, y));
  // The glowing band along its foot.
  float band = exp(-y * 14.0) * (0.45 + 0.55 * broad);
  float light = (streak * rise + 0.7 * band) * strength;
  // An arc fades out toward its ends; a whole ring meets itself.
  if(arc < 3.14) light *= smoothstep(0.0, 0.12, min(v_ah.x, 1.0 - v_ah.x));
  // Its colour wanders round the ring through its three foot colours (the necromancer's
  // greens: emerald, acid and sea-green) and deepens toward the top.
  float hue = ring_noise(u * 5.0 + time * 0.12, 5.0) * 2.0;
  vec3 low = hue < 1.0 ? mix(foot_1, foot_2, hue) : mix(foot_2, foot_3, hue - 1.0);
  vec3 c = mix(low, top_color, smoothstep(0.25, 0.95, y / max(top, 0.3)));
  c = mix(c, band_color, band * 0.6);
  color = vec4(c * light * 1.3, 1.0);
}")

(define-shader-entity spell-circle (fx-sprite)
  ((spell :initarg :spell :reader spell)
   (caster :initarg :caster :initform NIL :reader caster)
   (centre :initarg :centre :reader centre :documentation "The point on the floor it is drawn round.")
   (aurora :initform NIL :accessor circle-aurora)
   (lamp :initform NIL :accessor circle-lamp)
   (struck :initform NIL :accessor struck :documentation "Seconds since it struck, or NIL.")
   (rings-left :initform () :accessor rings-left :documentation "Rings of the strike yet to burst.")
   (sound :initform NIL :accessor circle-sound :documentation "Its loop through the wind-up.")))

(defun circle-radius (spell)
  (reduce #'max (spell-effects spell) :key #'effect-area :initial-value 0))

(defmethod initialize-instance :after ((circle spell-circle) &key)
  ;; Flat on the floor, facing up, just off it. Drawn for a radius of the strip's
  ;; :RADIUS metres (tools/draw_grave_circle.py), scaled to the spell's.
  (let* ((atlas (animation-atlas (sprite-animation circle)))
         (k (/ (circle-radius (spell circle)) (getf atlas :radius 2.5))))
    (nv* (scaling circle) (float k 0f0)))
  (!qfrom-angle (orientation circle) +vx+ #.(float (- (/ pi 2)) 0f0))
  (incf (vy (location circle)) 0.01))

(defmethod effect-origin ((source spell-circle)) (centre source))

(defmethod effect-direction ((source spell-circle) target)
  (v- (if (typep target 'creature) (location target) (feet target)) (centre source)))

;; It comes up from the floor, under any shield.
(defmethod effect-unblockable-p ((source spell-circle)) T)

(defun circle-strength (circle)
  "How bright CIRCLE's light is: rising through the wind-up, a flash as it strikes,
then fading."
  (let ((struck (struck circle)))
    (if struck
        (* (+ 1 *circle-flash*) (max 0.0 (- 1 (/ struck *circle-linger*))))
        (expt (min 1.0 (/ (age circle) (spell-windup (spell circle)))) 1.5))))

(defun light-circle (circle)
  "Raise CIRCLE's aurora and lamp, the first time it ticks in the scene."
  (let ((c (centre circle)))
    (setf (circle-sound circle) (start-loop (spell-sound (spell circle) :circle) c))
    (setf (circle-aurora circle) (make-instance 'aurora :centre c :radius (circle-radius (spell circle))))
    (enter (circle-aurora circle) (container circle))
    (setf (circle-lamp circle)
          (add-lamp (vec (vx c) (+ (vy c) 0.8) (vz c)) *circle-light-color* *circle-light-radius*
                    :flicker 0.15))))

(defun drop-aurora (circle)
  (when (circle-aurora circle)
    (despawn (circle-aurora circle))
    (setf (circle-aurora circle) NIL)))

(defun drop-circle-light (circle)
  (drop-aurora circle)
  (when (circle-lamp circle)
    (remove-lamp (circle-lamp circle))
    (setf (circle-lamp circle) NIL)))

;; A reset or rebuild takes the circle away before it is done.
(defmethod leave :after ((circle spell-circle) container)
  (setf (circle-sound circle) (stop-loop (circle-sound circle)))
  (drop-circle-light circle))

(defun in-circle-p (circle point radius)
  "True if feet at POINT, of a body RADIUS wide, stand in CIRCLE."
  (let* ((c (centre circle))
         (r (+ (circle-radius (spell circle)) (* 0.5 radius)))
         (dx (- (vx point) (vx c)))
         (dz (- (vz point) (vz c))))
    (and (< (+ (* dx dx) (* dz dz)) (* r r))
         (< (abs (- (vy point) (vy c))) *circle-reach-height*))))

(defun harvest (at height)
  "Wrench blood straight up out of something struck, standing at AT, HEIGHT tall."
  (spray-blood (vec (vx at) (+ (vy at) (* 0.5 height)) (vz at)) 0.0 0.0 *harvest-blood*
               :speed '(0.3 1.5) :rise '(1.2 1.5) :lift 5.0))

(defun strike-circle (circle)
  "CIRCLE strikes: everything living in it takes the spell, and the strike's first ring bursts up."
  (let ((spell (spell circle))
        (caster (caster circle)))
    (setf (struck circle) 0.0
          (rings-left circle) *strike-rings*
          (circle-sound circle) (stop-loop (circle-sound circle)))
    (play-sound (spell-sound spell :strike) (centre circle))
    (drop-aurora circle)
    (loop for c across *creatures*
          when (and (not (dead c)) (not (undead c)) (not (eq c caster))
                    (in-circle-p circle (location c) (body-radius c)))
            do (when (bleeds c) (harvest (location c) (sprite-height c)))
               (apply-spell spell c circle))
    (when (and *player* (< 0 (health *player*)) (in-circle-p circle (feet *player*) *player-radius*))
      (harvest (feet *player*) *player-height*)
      (apply-spell spell *player* circle))))

(defun burst-ring (circle ring)
  (destructuring-bind (fraction count) ring
    (let* ((c (centre circle))
           (r (* fraction (circle-radius (spell circle))))
           (turn (random (float (* 2 pi) 0f0))))
      (dotimes (k count)
        (let* ((a (+ turn (* k (/ (* 2 pi) count))))
               ;; A little scatter, so the rings don't look drawn with a compass.
               (rr (+ r (if (< 0 r) (- (random 0.3) 0.15) 0.0))))
          (spawn-standing-fx (strike-animation (spell circle)) (+ (vx c) (* rr (cos a))) (vy c)
                             (+ (vz c) (* rr (sin a))) (container circle)))))))

(defun sign-frame (age windup count)
  "The frame of a strip of COUNT, frames drawing a sign in and then a pulsing loop of 4, to
show AGE seconds into a wind-up of WINDUP."
  (let ((draw-in (- count 4))
        (progress (/ age (* *circle-draw-in* windup))))
    (if (< progress 1)
        (min (1- draw-in) (floor (* progress draw-in)))
        (+ draw-in (mod (floor (* age *circle-pulse-fps*)) 4)))))

;; Its own tick, not FX-SPRITE's: the frame follows the wind-up, and it lies flat.
(define-handler (spell-circle tick) (dt)
  (let* ((spell (spell spell-circle))
         (windup (spell-windup spell))
         (atlas (animation-atlas (sprite-animation spell-circle)))
         (count (getf atlas :frames)))
    (when (and (null (circle-lamp spell-circle)) (null (struck spell-circle)) (container spell-circle))
      (light-circle spell-circle))
    (unless (frozen-p)
      (incf (age spell-circle) dt)
      (let ((struck (struck spell-circle)))
        (cond (struck
               (setf struck (+ struck dt)
                     (struck spell-circle) struck)
               (let ((ring (first (rings-left spell-circle))))
                 (when (and ring (<= (* *strike-ring-delay* (- (length *strike-rings*) (length (rings-left spell-circle))))
                                     struck))
                   (burst-ring spell-circle ring)
                   (pop (rings-left spell-circle))))
               (when (< *circle-linger* struck)
                 (despawn spell-circle)))
              ((<= windup (age spell-circle))
               (strike-circle spell-circle)
               (burst-ring spell-circle (pop (rings-left spell-circle)))))))
    ;; The sign draws itself in, then pulses.
    (strip-uv (frame-uv spell-circle) atlas (sign-frame (age spell-circle) windup count) count)
    ;; The aurora rises and brightens, and so does the lamp.
    (let ((k (circle-strength spell-circle))
          (lamp (circle-lamp spell-circle))
          (aurora (circle-aurora spell-circle)))
      (when aurora
        (raise-aurora aurora (age spell-circle) windup k))
      (when lamp
        (let ((color (color lamp)))
          (setf (vx color) (* k (vx *circle-light-color*))
                (vy color) (* k (vy *circle-light-color*))
                (vz color) (* k (vz *circle-light-color*))))))))

(defun raise-aurora (aurora age windup k)
  "Bring AURORA up, AGE seconds into a wind-up of WINDUP, as bright as a lamp at K of its full."
  (destructuring-bind (low high) *aurora-height*
    (setf (aurora-height aurora) (+ low (* (- high low) (min 1.0 (/ age (* 0.8 windup)))))
          (aurora-strength aurora) (min 1.0 (* 1.6 k)))))

(defun place-circle (spell centre container caster)
  "Draw SPELL's circle on the floor round point CENTRE for CASTER."
  (let ((circle (make-instance 'spell-circle :spell spell :caster caster :centre (vcopy centre)
                                             :location (vcopy centre)
                                             :animation (find-fx-animation (circle-animation spell)))))
    (enter circle container)
    circle))

(defun cast-spell (spell origin direction container &key caster)
  "Deliver SPELL from ORIGIN along unit vector DIRECTION for CASTER, the player or a
creature; a :CIRCLE is drawn round ORIGIN, on the floor, and DIRECTION doesn't count.
Mana is the caster's business."
  (ecase (spell-delivery spell)
    (:projectile (launch-projectile spell origin direction container caster))
    (:circle (place-circle spell origin container caster))
    (:vortex (place-vortex spell origin direction container caster))))

(defparameter *spell-looks*
  '((:fire bolt-flight bolt-burst (1.5 0.8 0.3))
    (:frost frost-flight frost-burst (0.45 1.0 1.8))
    (:shock shock-flight shock-burst (1.6 1.5 0.5))
    (:drain drain-flight drain-burst (1.6 0.3 0.5))
    (:heal heal-flight heal-burst (0.5 1.6 0.4))
    (:arcane arcane-flight arcane-burst (1.1 0.4 1.7)))
  "(LOOK FLIGHT BURST LIGHT-COLOR) for each look a forged spell can have.")

;;; The spells.

(defun preload-spells (scene)
  "Load the sprites of every spell, which only appear mid-game, and of every look a forged
spell may have, which no spell in *SPELLS* need use."
  (loop for (nil flight burst) in *spell-looks*
        do (preload (make-instance 'fx-sprite :animation (find-fx-animation burst)) scene)
           (preload (make-instance 'spell-projectile :animation (find-fx-animation flight)) scene))
  (loop for spell being the hash-values of *spells*
        do (when (eq (spell-delivery spell) :vortex)
             (preload-vortex spell scene))
           (dolist (name (list (projectile-animation spell) (impact-animation spell)))
             (when name
               (preload (make-instance 'fx-sprite :animation (find-fx-animation name)) scene)))
           (when (strike-animation spell)
             (preload (make-instance 'upright-fx :animation (find-fx-animation (strike-animation spell))) scene))
           (when (projectile-animation spell)
             (preload (make-instance 'spell-projectile :spell spell
                                                       :animation (find-fx-animation (projectile-animation spell)))
                      scene))
           (when (circle-animation spell)
             (preload (make-instance 'spell-circle :spell spell :centre (vec 0 0 0)
                                                   :animation (find-fx-animation (circle-animation spell)))
                      scene)
             (preload (make-instance 'aurora :centre (vec 0 0 0) :radius 1.0) scene))))

(define-fx-animation bolt-flight "sprites/bolt/flight" :fps 12 :loop T :size 0.4)
(define-fx-animation bolt-burst "sprites/bolt/burst" :fps 14 :size 0.9)

(define-spell bolt (:delivery :projectile :projectile-speed 20.0 :pain-bonus 10
                    :projectile-animation 'bolt-flight :impact-animation 'bolt-burst)
  (:damage :magnitude '(6 10))
  (:knockback :magnitude '(4 4)))

;; The player's other starting spell: cast on themself, it needs no projectile.
(define-spell heal (:delivery :self)
  (:heal :magnitude '(15 20) :target-type :self))

;;; Looks: a forged spell (forge.lisp) flies and bursts as its element, or, with no
;;; damage, as its first effect: the bolt's frames, recoloured (tools/recolor_hue.py,
;;; data/sprites/spells/), with a glow to match.

(define-fx-animation frost-flight "sprites/spells/frost-flight" :fps 12 :loop T :size 0.4)
(define-fx-animation frost-burst "sprites/spells/frost-burst" :fps 14 :size 0.9)
(define-fx-animation shock-flight "sprites/spells/shock-flight" :fps 16 :loop T :size 0.4)
(define-fx-animation shock-burst "sprites/spells/shock-burst" :fps 16 :size 0.9)
(define-fx-animation drain-flight "sprites/spells/drain-flight" :fps 10 :loop T :size 0.4)
(define-fx-animation drain-burst "sprites/spells/drain-burst" :fps 14 :size 0.9)
(define-fx-animation heal-flight "sprites/spells/heal-flight" :fps 10 :loop T :size 0.4)
(define-fx-animation heal-burst "sprites/spells/heal-burst" :fps 14 :size 0.9)
(define-fx-animation arcane-flight "sprites/spells/arcane-flight" :fps 12 :loop T :size 0.4)
(define-fx-animation arcane-burst "sprites/spells/arcane-burst" :fps 14 :size 0.9)

(defun effects-look (effects)
  "The look of a spell of EFFECTS, a list of EFFECT: its first damage's element, else its
first effect's kind."
  (let ((damage (find :damage effects :key #'effect-kind)))
    (cond ((and damage (effect-element damage)))
          (damage :fire)
          (T (case (and effects (effect-kind (first effects)))
               (:drain :drain)
               ((:heal :ward) :heal)
               (:slow :frost)
               (T :arcane))))))

;;; Specs: a spell as plain data, for forged spells, which aren't in *SPELLS* and are saved
;;; by what they hold (save.lisp): (NAME DELIVERY &rest EFFECTS), each effect a plist of
;;; EFFECT initargs.

(defun spell-spec (spell)
  (list* (spell-name spell) (spell-delivery spell)
         (loop for e in (spell-effects spell)
               collect (list :kind (effect-kind e) :magnitude (copy-list (effect-magnitude e))
                             :duration (effect-duration e) :area (effect-area e)
                             :target-type (effect-target-type e) :element (effect-element e)))))

(defun spec-spell (spec)
  "A new spell made from SPEC, (NAME DELIVERY &rest EFFECT-PLISTS), with its look."
  (destructuring-bind (name delivery &rest effect-specs) spec
    (let* ((effects (loop for args in effect-specs
                          collect (apply #'make-instance 'effect
                                         :magnitude (copy-list (getf args :magnitude '(1 1)))
                                         args)))
           (look (assoc (effects-look effects) *spell-looks*)))
      (destructuring-bind (flight burst (r g b)) (rest look)
        (make-instance 'spell :name name :delivery delivery :effects effects
                              :projectile-speed 20.0 :pain-bonus 10
                              :projectile-animation flight :impact-animation burst
                              :light-color (vec r g b) :light-radius *bolt-light-radius*)))))

;; The acolyte's spell (creature.lisp): slower than the bolt, so a sidestep dodges it.
;; It flies on the bolt's frames, bigger and redder, until it has its own.
(define-fx-animation cinder-flight "sprites/bolt/flight" :fps 9 :loop T :size 0.55)

(define-spell cinder (:delivery :projectile :projectile-speed 9.0
                      :projectile-animation 'cinder-flight :impact-animation 'bolt-burst
                      :light-color (vec 1.8 0.35 0.12) :light-radius 4.5)
  (:damage :magnitude '(5 8)))

;; The necromancer's spells (creature.lisp). The grave skull flies slowly and curves
;; after the player, but turns slower than a late sidestep.
(define-fx-animation grave-skull-flight "sprites/grave/flight" :fps 10 :loop T :size 0.5)
(define-fx-animation grave-skull-burst "sprites/grave/burst" :fps 14 :size 1.0)

(define-spell grave-skull (:delivery :projectile :projectile-speed 6.0 :homing 1.0 :lifetime 5.0
                           :projectile-animation 'grave-skull-flight :impact-animation 'grave-skull-burst
                           :light-color (vec 0.4 1.8 0.5) :light-radius 4.0)
  (:damage :magnitude '(6 9)))

;; The grave circle: a pentagram drawn for a 2.5 m radius (tools/draw_grave_circle.py),
;; its cell 328 px at 64 px a metre; an aurora round it; then bone spikes burst up all
;; over it, the tallest 1.8 m.
(define-fx-animation grave-circle "sprites/grave/circle" :loop T :size (/ 328 64.0))
(define-fx-animation grave-spikes "sprites/grave/spikes" :fps 12 :size (/ 115 64.0))

(define-spell grave-spikes (:delivery :circle :windup 2.5
                            :circle-animation 'grave-circle
                            :strike-animation 'grave-spikes)
  (:damage :magnitude '(14 22) :area 2.5)
  (:knockback :magnitude '(3 3) :area 2.5))
