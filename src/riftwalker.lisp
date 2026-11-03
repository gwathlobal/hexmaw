(in-package #:hexmaw)

;;; The riftwalker: a masked assassin that steps through rifts in the air. It fights up close
;;; with a curved dagger, and moves things about. It blinks: a short jump to a random spot near
;;; it, every few seconds while it hunts, and often when it is hit or the player's projectile is
;;; about to reach it. And it throws rifts, slow projectiles that move whoever they strike (a
;;; sidestep dodges them, a raised shield stops them): a PULL puts the player in front of it,
;;; where its stab follows at once; a SWAP trades places with the player, who keeps facing the
;;; way they did, and a moment later it blinks in right behind them; a PUSH, when the player is on top of it, sends them
;;; off to a spot a medium walk away. It also CALLS an ally from across the level to stand in
;;; front of the player, a cast that a sign on the floor gives away and a flinch breaks.

(defparameter *riftwalker-height* 1.8 "Riftwalker height in metres, hood to feet.")
(defparameter *blink-range* '(3.0 6.0) "Metres a blink carries it, least and most.")
(defparameter *blink-cooldown* 3.0 "Seconds after a blink before the next one.")
(defparameter *blink-interval* '(4.0 8.0) "Seconds between the blinks it makes of its own accord while hunting.")
(defparameter *blink-dodge-chance* 35 "Percent chance it blinks away after a hit it lives through.")
(defparameter *blink-evade-chance* 50 "Percent chance it blinks out of the way of the player's projectile.")
(defparameter *rift-pull-range* '(6.0 16.0) "Metres from the player it throws a pull.")
(defparameter *rift-swap-range* '(5.0 14.0) "Metres from the player it throws a swap.")
(defparameter *pounce-delay* 0.4 "Seconds after a swap that it blinks in behind the player.")
(defparameter *rift-push-reach* 3.0 "Metres from its body's edge the player must be for a push.")
(defparameter *rift-pull-gap* 0.3 "Metres between its body and the player's where a pull puts them: inside its stab's reach.")
(defparameter *rift-away-walk* '(10.0 25.0)
  "Least and most metres of walking from where they stood to where a push sends the player.")
(defparameter *rift-away-within* 20.0 "Most metres, in a straight line, a push sends the player.")
(defparameter *call-min-distance* 8.0 "Metres an ally must be from the player to be worth calling.")
(defparameter *call-reach* 25.0 "Metres from the riftwalker an ally can be called from.")
(defparameter *call-distance* 2.0 "Metres from the player's body's edge to the called ally's.")
(defparameter *call-cast-time* 1.0 "Seconds from the call's start to the ally stepping through.")
(defparameter *rift-light-color* (vec 0.5 0.65 1.3) "The flash of light where something steps through a rift.")
(defparameter *rift-light-radius* 4.0)
(defparameter *call-light-color* (vec 0.8 1.0 2.2) "The call's sign's lamp, just before the ally steps through.")
(defparameter *call-light-radius* 4.0)

;; A rift in flight, a jagged diamond of void rimmed with light, one strip per colour
;; (tools/recolor_hue.py from one sheet), and the shards it bursts into.
(define-fx-animation rift-pull-flight "sprites/rift/pull" :fps 10 :loop T :size 0.45)
(define-fx-animation rift-swap-flight "sprites/rift/swap" :fps 10 :loop T :size 0.45)
(define-fx-animation rift-push-flight "sprites/rift/push" :fps 10 :loop T :size 0.45)
(define-fx-animation rift-burst "sprites/rift/burst" :fps 14 :size 0.8)
;; What is left in the air where something stepped through a rift: a crack as tall as a
;; body tearing open into void, snapping shut and scattering.
(define-fx-animation rift-flash "sprites/rift/flash" :fps 14 :size 1.8)
;; The call's sign under where the ally will step out (tools/draw_rift_sign.py).
(define-fx-animation rift-sign "sprites/rift/sign" :loop T :size (/ 139 64.0))

;; Each rift has its own colour, so the player can tell which is coming.
(define-spell rift-pull (:delivery :projectile :projectile-speed 10.0
                         :projectile-animation 'rift-pull-flight :impact-animation 'rift-burst
                         :light-color (vec 1.4 0.5 2.2) :light-radius 4.0)
  (:teleport-to))

(define-spell rift-swap (:delivery :projectile :projectile-speed 10.0
                         :projectile-animation 'rift-swap-flight :impact-animation 'rift-burst
                         :light-color (vec 2.0 1.7 0.8) :light-radius 4.0)
  (:swap))

(define-spell rift-push (:delivery :projectile :projectile-speed 10.0
                         :projectile-animation 'rift-push-flight :impact-animation 'rift-burst
                         :light-color (vec 0.4 1.6 2.0) :light-radius 4.0)
  (:teleport-away))

;; A prowling stalk, four frames per view; its cells are 120 px tall for the rise on the passing
;; frames, the standing riftwalker 115 px. The frame follows the distance walked (STRIDE).
(define-fx-animation riftwalker-walk "sprites/riftwalker/walk" :loop T :size (* *riftwalker-height* 120/115))
;; A low, quick thrust of the dagger: wind-up, lunge, strike, recover.
;; Four frames per view; its cells are 114 px tall, the riftwalker crouched lower than standing
;; (115 px) in all of them. The frames run on the stab's frame times, so :FPS is unused.
(define-fx-animation riftwalker-stab "sprites/riftwalker/stab" :size (* *riftwalker-height* 114/115))
;; The rift torn open in the left hand and thrown (every rift and the call): gather, the
;; crack held up (what the call's cast holds), release, recover. Its cells are 126 px tall to
;; fit the rift held over the hood.
(define-fx-animation riftwalker-cast "sprites/riftwalker/cast" :size (* *riftwalker-height* 126/115))
;; The flinch: jolt, then stagger, two frames per view over *STAGGER-TIME*.
(define-fx-animation riftwalker-hurt "sprites/riftwalker/hurt" :size (* *riftwalker-height* 120/115))
;; The mask cracks, the dagger falls, and it folds to the floor face down: the corpse. Front
;; view only; its cells are 120 px tall, the jolted riftwalker in frame 1 at the turnaround's 115.
(define-fx-animation riftwalker-death "sprites/riftwalker/death" :fps 9 :size (* *riftwalker-height* 120/115))

(defun riftwalker-abilities ()
  ;; The stab first: an ability with no spell answers ATTACK-SPELL with the first's, so it
  ;; stays a melee attacker.
  (list (make-instance 'ability :name :stab :animation 'riftwalker-stab
                                :frame-times '(0.3 0.1 0.2 0.3) :hit-frame 2 :pause 0.5)
        ;; A pull or a swap leads straight into the stab: a short pause after.
        (make-instance 'ability :name :pull :spell 'rift-pull :animation 'riftwalker-cast
                                :frame-times '(0.35 0.35 0.2 0.3) :hit-frame 2 :pause 0.2 :cooldown 8.0)
        (make-instance 'ability :name :swap :spell 'rift-swap :animation 'riftwalker-cast
                                :frame-times '(0.35 0.35 0.2 0.3) :hit-frame 2 :pause 0.2 :cooldown 10.0)
        (make-instance 'ability :name :push :spell 'rift-push :animation 'riftwalker-cast
                                :frame-times '(0.25 0.25 0.2 0.3) :hit-frame 2 :pause 0.6 :cooldown 12.0)
        (make-instance 'ability :name :call :animation 'riftwalker-cast
                                :frame-times (list 0.3 (- *call-cast-time* 0.3) 0.25 0.35)
                                :hit-frame 2 :pause 0.6 :cooldown 14.0)))

;; Sliced at 115 px tall, so its art pixels are the imp's size (96 px for 1.5 m).
(define-asset (hexmaw riftwalker-turnaround) image
    #p"sprites/riftwalker/turnaround.png"
  :min-filter :nearest :mag-filter :nearest)

(define-shader-entity riftwalker (ability-user creature)
  ((texture :initform (// 'hexmaw 'riftwalker-turnaround))
   (atlas :initform (read-atlas "sprites/riftwalker/turnaround.lisp"))
   (sprite-height :initform *riftwalker-height*)
   (walk-animation :initform 'riftwalker-walk)
   (hurt-animation :initform 'riftwalker-hurt)
   (death-animation :initform 'riftwalker-death)
   (gibs :initform '((:flesh 0 0 1 1 2 4 5 6 6 7)))
   (abilities :initform (riftwalker-abilities))
   (cooldowns :initform (list :pull 0.0 :swap 0.0 :push 0.0 :call 0.0))
   (attack-damage :initform '(6 10))
   (attack-reach :initform 0.8)
   (cast-offset :initform -0.25)
   (walk-speed :initform 1.3)
   (chase-speed :initform 2.6)
   (wander-radius :initform 3.0)
   (flanks :initform T)
   ;; Its casts are hard to break with a blow: a sidestep is the answer to a rift.
   (pain-chance :initform 22)
   (max-health :initform 35)
   (blink-cooldown :initform 0.0 :accessor blink-cooldown :documentation "Seconds before it can blink again.")
   (blink-timer :initform 5.0 :accessor blink-timer
                :documentation "Seconds of hunting until it blinks of its own accord.")
   (pounce :initform 0.0 :accessor pounce
           :documentation "Seconds until it blinks in behind the player after a swap; 0 for none.")
   (call-target :initform NIL :accessor call-target :documentation "The ally it is calling.")
   (call-point :initform (vec 0 0 0) :reader call-point
               :documentation "Where on the floor the ally it is calling will step out.")))

;; A melee hunter, but its casts turn after the player until they leave, as a caster's do.
(defmethod ranged-p ((riftwalker riftwalker))
  (and (eq (brain riftwalker) :attacking)
       (not (eq :stab (ability-name (current-ability riftwalker))))))

;; Its rifts are meant for the player: they pass through every creature on the way.
(defmethod spares-p ((riftwalker riftwalker) target) T)

(defun random-between (range)
  (destructuring-bind (lo hi) range
    (+ lo (* (- hi lo) (/ (random 1000 *roll-random*) 1000.0)))))

;;; Where a rift puts things.

(defun actor-step (actor)
  (if (typep actor 'player) *step-height* (step-height actor)))

(defun bearing (from to)
  "The yaw from point FROM toward point TO."
  (atan (- (vx to) (vx from)) (- (vz from) (vz to))))

(defun spot-around (centre yaw distance actor &key sight-of from)
  "A free spot for ACTOR's body DISTANCE metres from CENTRE, as near the bearing YAW as can
be: in sight of SIGHT-OF if given, on FROM's side of the arena's walls. Or NIL."
  (loop for turn in '(0.0 0.5 -0.5 1.0 -1.0 1.6 -1.6 2.3 -2.3 3.1)
        for a = (+ yaw turn)
        for p = (vec (+ (vx centre) (* distance (sin a))) (vy centre) (- (vz centre) (* distance (cos a))))
        for to = (free-spot p (body-radius actor) (body-height actor) :search 1 :ignore actor
                                                                        :sight-of sight-of :from (or from centre))
        when to return to))

(defun spot-away (actor)
  "A free spot ACTOR can walk back from, *RIFT-AWAY-WALK* metres of walking away from where
it stands and no more than *RIFT-AWAY-WITHIN* in a straight line, dry, on its side of the
arena's walls. Or NIL."
  (let* ((*nav-hazards* :avoid)
         (from (body-feet actor))
         (r (body-radius actor))
         (h (body-height actor)))
    (destructuring-bind (least most) *rift-away-walk*
      (car (last (nav-reachable-spot from r h (actor-step actor)
                                     :within *rift-away-within* :min-distance least :max-walk most
                                     :test (lambda (p)
                                             (and (same-arena-side-p from p (+ r 0.5))
                                                  (not (body-overlapping (vx p) (+ (vy p) 0.05) (vz p) (float r 0f0)
                                                                         (- (float h 0f0) 0.05) actor))))))))))

;;; Moving through a rift.

(defgeneric teleport-actor (actor to &key yaw)
  (:documentation "Put ACTOR at the floor point TO at once, turned to YAW if given."))

(defmethod teleport-actor ((player player) to &key yaw)
  (teleport-player player to :yaw yaw))

(defmethod teleport-actor ((creature creature) to &key yaw)
  (clear-whirl creature)
  (v<- (location creature) to)
  (let ((kb (momentum creature))) (setf (vx kb) 0.0 (vy kb) 0.0 (vz kb) 0.0))
  (when yaw
    (setf (facing creature) (float yaw 0f0)))
  (stop-walking creature 0.25))

(defun rift-flash (actor container)
  "Light and a burst at the middle of ACTOR's body, where it is stepping through a rift. Not
for the player, whose view flashes instead: the burst would stand in front of the camera."
  (when (and container (not (typep actor 'player)))
    (let ((feet (body-feet actor)))
      (attach-glow (spawn-fx 'rift-flash (vec (vx feet) (+ (vy feet) (* 0.5 (body-height actor))) (vz feet)) container)
                   *rift-light-color* *rift-light-radius*))))

(defun rift-move (actor to &key yaw (container (and *player* (container *player*))))
  "Step ACTOR through a rift to TO, a flash where it leaves and where it arrives."
  (rift-flash actor container)
  (teleport-actor actor to :yaw yaw)
  (rift-flash actor container))

;;; The rifts' effects, on the player, and on a creature one strikes once a knight's shield has
;;; sent it back as the knight's own.

(defun rift-stopped-p (target source)
  "True if TARGET, the player, stops the rift SOURCE brings with a raised shield; or TARGET
is a creature that nothing moves (a sleeping boss)."
  (if (typep target 'player)
      (and (not (effect-unblockable-p source)) (shield-blocks-p target (effect-origin source)))
      (or (dormant-p target) (dead target))))

(defun live-caster (source)
  (let ((caster (caster source)))
    (and (typep caster 'creature) (not (dead caster)) caster)))

(defmethod apply-effect ((kind (eql :teleport-to)) effect target source)
  (let ((caster (live-caster source)))
    (unless (or (null caster) (rift-stopped-p target source))
      (let* ((at (location caster))
             (to (spot-around at (bearing at (body-feet target))
                              (+ (body-radius caster) (body-radius target) *rift-pull-gap*) target
                              :sight-of at :from (body-feet target))))
        (when to
          (rift-move target to :yaw (bearing to at))
          (when (typep caster 'riftwalker)
            (face-player caster)))))))

(defmethod apply-effect ((kind (eql :teleport-away)) effect target source)
  (unless (rift-stopped-p target source)
    (let ((to (spot-away target)))
      (when to
        (rift-move target to)))))

(defmethod apply-effect ((kind (eql :swap)) effect target source)
  (let ((caster (live-caster source)))
    (unless (or (null caster) (rift-stopped-p target source))
      (let* ((here (vcopy (body-feet target)))
             (there (vcopy (location caster)))
             (to-there (free-spot there (body-radius target) (body-height target) :search 1 :ignore caster
                                                                                   :from here))
             (to-here (free-spot here (body-radius caster) (body-height caster) :search 1 :ignore target
                                                                                 :from there)))
        (when (and to-there to-here)
          ;; The target keeps its facing, so the caster ends up behind it.
          (rift-move target to-there)
          (rift-move caster to-here :yaw (bearing to-here to-there))
          (when (and (typep caster 'riftwalker) (typep target 'player))
            (setf (pounce caster) *pounce-delay*)))))))

;;; The blink.

(defun can-blink-p (riftwalker)
  (and (not (dead riftwalker))
       (not (dormant-p riftwalker))
       (<= (blink-cooldown riftwalker) 0)
       (not (whirl riftwalker))
       (not (flung riftwalker))
       (not (afloat-p riftwalker))
       (<= (rising riftwalker) 0)
       *player* (< 0 (health *player*))))

(defun blink-spot (riftwalker)
  "A random free spot *BLINK-RANGE* metres from RIFTWALKER, with a clear line from it and to
the player, and not on top of them. Or NIL."
  (let* ((loc (location riftwalker))
         (feet (feet *player*))
         (start (* 2 pi (/ (random 360 *roll-random*) 360.0)))
         (d (random-between *blink-range*)))
    (loop for i below 8
          for yaw = (+ start (* i (/ pi 4)))
          for p = (vec (+ (vx loc) (* d (sin yaw))) (vy loc) (- (vz loc) (* d (cos yaw))))
          for to = (free-spot p (body-radius riftwalker) (sprite-height riftwalker)
                              :search 1 :ignore riftwalker :sight-of feet :from loc)
          when (and to
                    (clear-path-p loc to 1.0)
                    (< (+ (body-radius riftwalker) *player-radius* 1.0)
                       (sqrt (+ (expt (- (vx to) (vx feet)) 2) (expt (- (vz to) (vz feet)) 2)))))
            return to)))

(defun pounce-spot (riftwalker)
  "A free spot right behind the player, in RIFTWALKER's stab's reach; or NIL."
  (let ((feet (feet *player*)))
    (spot-around feet (+ (vy (rotation *player*)) pi) (+ (body-radius riftwalker) *player-radius* 0.3) riftwalker
                 :sight-of feet :from feet)))

(defun blink (riftwalker &optional (to (blink-spot riftwalker)))
  "Step RIFTWALKER through a rift to TO, by default a random spot near it, breaking off
whatever it was doing. True if it went."
  (when to
    (setf (blink-cooldown riftwalker) *blink-cooldown*
          (blink-timer riftwalker) (random-between *blink-interval*)
          (stagger riftwalker) 0.0
          (call-target riftwalker) NIL)
    (rift-move riftwalker to :container (container riftwalker))
    (face-player riftwalker)
    T))

(defmethod react-to-hit ((riftwalker riftwalker))
  (when (and (can-blink-p riftwalker) (< (random 100 *roll-random*) *blink-dodge-chance*))
    (blink riftwalker)))

(defmethod evade-projectile ((riftwalker riftwalker) projectile)
  (when (and (can-blink-p riftwalker) (< (random 100 *roll-random*) *blink-evade-chance*))
    (setf (alert riftwalker) (max (alert riftwalker) *alert-time*))
    (blink riftwalker)))

;;; The call.

(defun callable-p (riftwalker c)
  (and (not (eq c riftwalker))
       (not (dead c))
       (not (dormant-p c))
       (not (typep c 'boss))
       (attacker-p c)
       (<= (rising c) 0)
       (not (whirl c))
       (not (flung c))
       (not (afloat-p c))
       (< *call-min-distance* (player-distance c))
       ;; Not one another riftwalker is calling already.
       (loop for other across *creatures*
             never (and (typep other 'riftwalker) (not (eq other riftwalker)) (eq c (call-target other))))))

(defun call-spot (riftwalker c)
  "Where an ally C called to the player steps out: in front of them, in their sight, but to
the side of the way from RIFTWALKER to them, so it doesn't stand in the riftwalker's line."
  (let* ((feet (feet *player*))
         (facing (vy (rotation *player*)))
         (toward (bearing feet (location riftwalker)))
         ;; Of the player's front quarters, the one further from the riftwalker.
         (yaw (if (< (angle-between (+ facing 0.8) toward) (angle-between (- facing 0.8) toward))
                  (- facing 0.8)
                  (+ facing 0.8))))
    (spot-around feet yaw (+ *player-radius* (body-radius c) *call-distance*) c
                 :sight-of feet :from feet)))

(defun ally-to-call (riftwalker)
  "The ally nearest RIFTWALKER worth calling to the player, within *CALL-REACH*, and the spot
it would step out on; or NIL."
  (let ((loc (location riftwalker))
        (best NIL) (spot NIL) (best-d *call-reach*))
    (loop for c across *creatures*
          for at = (location c)
          for d = (sqrt (+ (expt (- (vx at) (vx loc)) 2) (expt (- (vz at) (vz loc)) 2)))
          when (and (< d best-d) (callable-p riftwalker c))
            do (let ((to (call-spot riftwalker c)))
                 (when to (setf best c spot to best-d d))))
    (values best spot)))

(defun begin-call (riftwalker ally spot)
  (setf (call-target riftwalker) ally)
  (v<- (call-point riftwalker) spot)
  (start-ability riftwalker :call)
  (enter (make-instance 'rift-sign :caster riftwalker :centre (vcopy spot) :location (vcopy spot)
                                   :animation (find-fx-animation 'rift-sign))
         (container riftwalker)))

(defun release-call (riftwalker)
  (let ((ally (call-target riftwalker))
        (spot (call-point riftwalker)))
    (setf (call-target riftwalker) NIL)
    (when (and ally (not (dead ally)) (not (whirl ally)) (not (flung ally)))
      ;; Something may have stepped onto the spot since.
      (let ((to (free-spot spot (body-radius ally) (sprite-height ally) :search 1 :ignore ally)))
        (when to
          (rift-move ally to :yaw (bearing to (feet *player*)) :container (container riftwalker))
          (setf (alert ally) (max (alert ally) *alert-time*)))))))

(defun calling-p (riftwalker)
  "True while RIFTWALKER's call has yet to bring its ally: how long its sign stays."
  (and (typep riftwalker 'riftwalker)
       (not (dead riftwalker))
       (call-target riftwalker)
       (eq :call (ability-name (current-ability riftwalker)))
       (winding-up-p riftwalker)))

;;; Hunting.

(defun in-range-p (distance range)
  (destructuring-bind (lo hi) range (<= lo distance hi)))


(defmethod special-attack ((riftwalker riftwalker))
  "Call an ally; push away a player on top of it while it is hurt or they hide behind their
shield; or throw a pull or a swap at one in range. True if it started one."
  (let* ((distance (player-distance riftwalker))
         (seen (clear-path-p (location riftwalker) (feet *player*) (cast-height riftwalker))))
    (or (and (ready-p riftwalker :call)
             (multiple-value-bind (ally spot) (ally-to-call riftwalker)
               (when ally
                 (begin-call riftwalker ally spot)
                 T)))
        (and seen
             (ready-p riftwalker :push)
             (< distance (+ (body-radius riftwalker) *player-radius* *rift-push-reach*))
             (or (< (health riftwalker) (* 0.5 (max-health riftwalker)))
                 (< 0 (block-raise *player*)))
             (progn (start-ability riftwalker :push) T))
        (let ((pull (and (ready-p riftwalker :pull) (in-range-p distance *rift-pull-range*)))
              (swap (and (ready-p riftwalker :swap) (in-range-p distance *rift-swap-range*))))
          (when (and seen (or pull swap))
            (start-ability riftwalker (cond ((and pull swap) (if (= 0 (random 2 *roll-random*)) :pull :swap))
                                            (pull :pull)
                                            (T :swap)))
            T)))))

(defmethod release-attack ((riftwalker riftwalker))
  (let ((ability (current-ability riftwalker)))
    (case (ability-name ability)
      (:stab (call-next-method))
      (:call (release-call riftwalker))
      (T (release-attack-spell riftwalker)))
    (when (< 0 (ability-cooldown ability))
      (setf (getf (cooldowns riftwalker) (ability-name ability)) (ability-cooldown ability)))))

(define-handler (riftwalker tick :after) (dt)
  (unless (frozen-p)
    (run-cooldowns riftwalker dt)
    (setf (blink-cooldown riftwalker) (max 0.0 (- (blink-cooldown riftwalker) dt)))
    ;; Back to the stab once an ability is over, so the next blow in reach is one.
    (unless (eq (brain riftwalker) :attacking)
      (setf (current-ability riftwalker) (first (abilities riftwalker))
            (call-target riftwalker) NIL))
    ;; The swap's follow-up, whatever the blink's cooldown.
    (when (and (< 0 (pounce riftwalker)) (<= (decf (pounce riftwalker) dt) 0))
      (setf (pounce riftwalker) 0.0)
      (let ((to (and (not (dead riftwalker)) (not (whirl riftwalker)) (pounce-spot riftwalker))))
        (when to (blink riftwalker to))))
    (when (and (hunting-p riftwalker) (not (eq (brain riftwalker) :attacking)) (can-blink-p riftwalker)
               (<= (decf (blink-timer riftwalker) dt) 0))
      (unless (blink riftwalker)
        (setf (blink-timer riftwalker) 1.0)))))

;;; The call's sign: it draws itself in on the floor where the ally will step out, under a
;;; brightening lamp, and goes when the call does, brought or broken.

(define-shader-entity rift-sign (fx-sprite)
  ((caster :initarg :caster :initform NIL :reader caster)
   (centre :initarg :centre :reader centre)
   (lamp :initform NIL :accessor sign-lamp)))

(defmethod initialize-instance :after ((sign rift-sign) &key)
  ;; Flat on the floor, facing up, just off it.
  (!qfrom-angle (orientation sign) +vx+ #.(float (- (/ pi 2)) 0f0))
  (incf (vy (location sign)) 0.01))

(defmethod leave :after ((sign rift-sign) container)
  (when (sign-lamp sign)
    (remove-lamp (sign-lamp sign))
    (setf (sign-lamp sign) NIL)))

;; Its own tick, not FX-SPRITE's: the frame follows the cast, and it lies flat.
(define-handler (rift-sign tick) (dt)
  (let ((c (centre rift-sign)))
    (when (and (null (sign-lamp rift-sign)) (container rift-sign))
      (setf (sign-lamp rift-sign)
            (add-lamp (vec (vx c) (+ (vy c) 0.6) (vz c)) (vec 0 0 0) *call-light-radius* :flicker 0.2))))
  (unless (frozen-p)
    (incf (age rift-sign) dt)
    (unless (calling-p (caster rift-sign))
      (despawn rift-sign)))
  (let* ((atlas (animation-atlas (sprite-animation rift-sign)))
         (count (getf atlas :frames))
         (k (min 1.0 (/ (age rift-sign) *call-cast-time*)))
         (lamp (sign-lamp rift-sign)))
    (strip-uv (frame-uv rift-sign) atlas (sign-frame (age rift-sign) *call-cast-time* count) count)
    (when lamp
      (let ((color (color lamp)))
        (setf (vx color) (* k (vx *call-light-color*))
              (vy color) (* k (vy *call-light-color*))
              (vz color) (* k (vz *call-light-color*)))))))

(defun preload-riftwalker (scene)
  "Load what a riftwalker spawns mid-game: the flash of a rift and the call's sign."
  (preload (make-instance 'fx-sprite :animation (find-fx-animation 'rift-flash)) scene)
  (preload (make-instance 'rift-sign :centre (vec 0 0 0) :animation (find-fx-animation 'rift-sign)) scene))

;;; As a boss (boss.lisp): the Rift Lord. Its powers' attacks show its cast.

(define-shader-entity riftwalker-boss (boss riftwalker) ())

(defmethod power-animation ((boss riftwalker-boss)) 'riftwalker-cast)
