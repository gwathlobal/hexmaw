(in-package #:hexmaw)

;;; The boss at the end of a run: an empowered form of one of the seven monsters, waiting
;;; in the arena block the last level ends in. It is drawn about 3 m tall, glowing, and
;;; keeps its kind's own attacks, with three powers on top: two from the start and a third
;;; when it enrages at half health. Which kind and which powers come from the level's seed
;;; (MAKE-BOSS, from *BLOCK-RANDOM*), so a run always meets the same boss.
;;;
;;; It sleeps (DORMANT-P: it neither thinks nor takes harm) until the player is
;;; *ARENA-TRIGGER-DEPTH* inside the arena's doorway. Then the gate drops behind them
;;; (SEAL-ARENA), and it hunts for good. Killing it wins the run (WIN-RUN): the victory
;;; screen comes up *VICTORY-DELAY* after its death animation is over.
;;;
;;; A power is a BOSS-POWER: an attack with its own frame times and cooldown, run through
;;; the creature's attack machinery (SPECIAL-ATTACK starts it, the attack readers answer for
;;; it while BOSS-POWER names it), or a passive that changes the boss while it has it. Each
;;; power may be denied to kinds or traits (:FLYER, :CASTER), and none copies the kind's own.

(defparameter *boss-kinds*
  '(("imp" imp-boss imp "Imp Overlord" 2.0 ())
    ("acolyte" acolyte-boss acolyte "High Acolyte" 1.7 (:caster))
    ("knight" knight-boss knight "Black Knight" 1.6 ())
    ("harpy" harpy-boss harpy "Harpy Queen" 1.7 (:flyer))
    ("necromancer" necromancer-boss necromancer "Archnecromancer" 1.5 (:caster))
    ("ogre" ogre-boss ogre "Ogre Warlord" 1.3 ())
    ("gale-wraith" wraith-boss gale-wraith "Storm Wraith" 1.7 (:flyer :caster)))
  "What a boss can be: the kind as a spawn names it, the boss's class, the class it is an
empowered form of, its title, how much bigger it is drawn, and its traits, which deny it
powers. Every kind is as likely.")

(defparameter *boss-override* NIL
  "For testing: a kind from *BOSS-KINDS* and, optionally, its three powers, which every boss
then gets, as (\"ogre\" :fire-volley :summon :blink). NIL for the seed's choice.")

(defparameter *boss-health* 500)
(defparameter *boss-pain-chance* 10 "Percent: few hits make it flinch, so it can't be held.")
(defparameter *boss-damage-scale* 1.5 "Its melee blow's damage against its kind's.")
(defparameter *boss-max-knockback* 0.2 "Most of a blow's knockback it takes.")
(defparameter *boss-max-radius* 1.3 "Widest its body gets, scaled up.")
(defparameter *boss-hover* 1.0 "Metres over the floor a flying boss keeps, so its body is in the sword's reach.")
(defparameter *boss-power-gap* 2.0 "Seconds after a power before it may start another: its own attacks get a turn.")
(defparameter *boss-enrage-at* 0.5 "Share of its health at which it enrages.")
(defparameter *boss-enrage-speed* 1.25 "How much faster it moves enraged.")
(defparameter *boss-enrage-attack-speed* 1.15 "How much faster its attacks run enraged.")
(defparameter *boss-enrage-pause* 0.6 "Its pauses after attacks, enraged, against before.")
(defparameter *boss-enrage-cooldown* 0.75 "Its powers' cooldowns, enraged, against before.")
(defparameter *boss-roar-time* 1.0 "Seconds it stands roaring when it enrages.")
(defparameter *haste-speed* 1.35 "How much faster Haste makes its walk and its attacks.")
(defparameter *boss-max-minions* 4 "Most summoned creatures alive at once that Summon still calls more with.")
(defparameter *boss-quake-radius* 5.0 "Metres its Shockwave reaches.")
(defparameter *boss-quake-damage* '(12 20))
(defparameter *victory-delay* 2.0 "Seconds from the end of its death animation to the victory screen.")
(defparameter *arena-trigger-depth* 2.0 "Metres inside the arena's doorway at which the gate drops.")
(defparameter *gate-drop-time* 0.3 "Seconds the gate takes to fall.")

(defparameter *boss-glow-color* (vec 1.0 0.42 0.12) "The rim's colour, and its lamp's.")
(defparameter *boss-shade* (vec 1.0 0.78 0.7) "What its whole body is multiplied by, a warm cast.")
(defparameter *boss-light-radius* 7.0)
(defparameter *ward-colors*
  (list (vec 0.55 0.25 1.0) (vec 0.75 0.4 1.0) (vec 0.4 0.3 1.0) (vec 0.3 0.1 0.65) (vec 0.85 0.7 1.0))
  "Warded's arc, as *GRAVE-AURORA-COLORS*: violets. Read when the arc is made.")
(defparameter *ward-reach* 0.6 "Metres outside its body that Warded's arc stands.")
(defparameter *ward-height* 1.4 "Metres Warded's arc rises.")
(defparameter *ward-strength* 0.8)

(defun boss-kind-entry (kind)
  (or (assoc kind *boss-kinds* :test #'string-equal)
      (error "No boss kind ~s." kind)))

;;; The arena: the block the boss waits in, and the gate across its doorway.

(defclass arena ()
  ((block :initarg :block :reader arena-block :documentation "Its MAP-BLOCK.")
   (door :initarg :door :reader arena-door :documentation "The CONNECTOR of its one doorway.")
   (boss :initarg :boss :initform NIL :accessor arena-boss)
   (gate :initform NIL :accessor arena-gate :documentation "The gate's GATE-SPRITE, once SETUP-SCENE has made it.")
   (gate-solid :initform NIL :accessor gate-solid)
   (sealed :initform NIL :accessor sealed :documentation "True once the gate has dropped.")
   (gate-drop :initform 0.0 :accessor gate-drop :documentation "How far it has fallen, 0 up to 1 down.")))

(defvar *arena* NIL "The level's ARENA, or NIL. BUILD-LEVEL forgets it.")

(defun note-arena (map-block connectors)
  "PLACE-BLOCK has just placed an arena: remember it, with the boss it spawned."
  (setf *arena* (make-instance 'arena :block map-block :door (first connectors)
                                      :boss (find-if (lambda (c) (typep c 'boss)) *creatures* :from-end T))))

(defun direction-step (direction)
  "DIRECTION as a step across, X then Z."
  (ecase direction
    (:north (values 0 -1)) (:south (values 0 1)) (:west (values -1 0)) (:east (values 1 0))))

(defun gate-box (arena)
  "The corners of ARENA's gate let down, as six values: across the doorway, in the middle of
its wall, from the floor into the lintel, and a little into each jamb."
  (let* ((door (arena-door arena))
         (p (connector-location door)))
    (multiple-value-bind (dx dz) (direction-step (connector-direction door))
      (multiple-value-bind (width height) (connector-size (connector-kind door))
        ;; The doorway's wall runs 0.5 m inward from the block's face, where P is.
        (let* ((cx (- (vx p) (* 0.25 dx)))
               (cz (- (vz p) (* 0.25 dz)))
               (across (+ (/ width 2) 0.05))
               (hx (if (= 0 dx) across 0.1))
               (hz (if (= 0 dz) across 0.1)))
          (values (- cx hx) (vy p) (- cz hz) (+ cx hx) (+ (vy p) height 0.5) (+ cz hz)))))))

(defparameter *gate-raise* 3.52 "Metres the gate stands up in the wall over the doorway while it is open.")

;; An ornate iron portcullis, flat-on, its gaps see-through: art/gate/portcullis-2.png
;; (art/prompts/gate-portcullis.txt), sliced at the monsters' 64 px per metre.
(define-asset (hexmaw arena-gate) image
    #p"sprites/gate/gate.png"
  :min-filter :nearest :mag-filter :nearest)

(define-shader-entity gate-sprite (billboard)
  ((texture :initform (// 'hexmaw 'arena-gate))
   (atlas :initform (read-atlas "sprites/gate/gate.lisp")))
  (:documentation "The arena's gate: a sprite lit like the monsters, but turned for good to face
into the arena instead of toward the camera, standing in the middle of the doorway's wall."))

;; Its own tick, not BILLBOARD's: it never turns, and it has one frame.
(define-handler (gate-sprite tick) ()
  (let ((atlas (atlas gate-sprite)))
    (strip-uv (frame-uv gate-sprite) atlas 0 (getf atlas :frames))))

(defun add-arena-gate (container)
  "Make the gate of the level's arena, up in the wall over its doorway. SETUP-SCENE calls
it once the level is built."
  (when *arena*
    (multiple-value-bind (x0 y0 z0 x1 y1 z1) (gate-box *arena*)
      (multiple-value-bind (dx dz) (direction-step (connector-direction (arena-door *arena*)))
        (let ((gate (make-instance 'gate-sprite :location (vec (/ (+ x0 x1) 2) y0 (/ (+ z0 z1) 2))
                                                ;; As wide as the doorway and a little into each jamb.
                                                :sprite-height (max (- x1 x0) (- z1 z0)))))
          ;; The quad faces +Z; turn it to face in, against the doorway's way out.
          (!qfrom-angle (orientation gate) +vy+ (float (atan (- dx) (- dz)) 0f0))
          (setf (arena-gate *arena*) gate
                (gate-solid *arena*) (make-solid x0 y0 z0 x1 y1 z1)
                (gate-drop *arena*) (if (sealed *arena*) 1.0 0.0))
          (enter gate container)
          (place-gate *arena*))))))

(defun place-gate (arena)
  (let ((gate (arena-gate arena)))
    (when gate
      (setf (vy (location gate))
            (float (+ (vy (connector-location (arena-door arena))) (* *gate-raise* (- 1 (gate-drop arena)))) 0f0)))))

(defun seal-arena (&key instant)
  "Drop the gate behind the player and wake the boss. INSTANT drops it at once (a load)."
  (let ((arena *arena*))
    (when (and arena (not (sealed arena)))
      (setf (sealed arena) T)
      (if instant
          (setf (gate-drop arena) 1.0)
          (play-sound :gate-drop (connector-location (arena-door arena))))
      (place-gate arena)
      ;; Solid at once, while it still falls: the player is already through.
      (vector-push-extend (gate-solid arena) *solids*)
      (index-solids)
      (let ((boss (arena-boss arena)))
        (when boss
          (setf (dormant boss) NIL
                (alert boss) *alert-time*))))))

(defun unseal-arena ()
  "Raise the gate and put the boss back to sleep, as the level was built."
  (let ((arena *arena*))
    (when arena
      (when (sealed arena)
        (let ((i (position (gate-solid arena) *solids*)))
          (when i
            (replace *solids* *solids* :start1 i :start2 (1+ i))
            (decf (fill-pointer *solids*))
            (index-solids))))
      (setf (sealed arena) NIL
            (gate-drop arena) 0.0)
      (place-gate arena)
      (let ((boss (arena-boss arena)))
        (when boss (reset-boss boss))))))

(defun player-in-arena-p (arena depth)
  "True if the player stands in ARENA's block, at least DEPTH metres in from its doorway."
  (let* ((feet (feet *player*))
         (door (arena-door arena))
         (p (connector-location door))
         (low (map-block-low (arena-block arena)))
         (high (map-block-high (arena-block arena))))
    (multiple-value-bind (dx dz) (direction-step (connector-direction door))
      (and (< (vx low) (vx feet) (vx high))
           (< (vz low) (vz feet) (vz high))
           (< (vy low) (vy feet) (vy high))
           ;; Inward is against the doorway's facing.
           (< depth (- (+ (* dx (- (vx feet) (vx p))) (* dz (- (vz feet) (vz p))))))))))

(defun arena-contains-p (point margin)
  "True if POINT is in the arena's block at least MARGIN metres from its bounds (T with no arena)."
  (or (null *arena*)
      (let ((low (map-block-low (arena-block *arena*)))
            (high (map-block-high (arena-block *arena*))))
        (and (< (+ (vx low) margin) (vx point) (- (vx high) margin))
             (< (+ (vz low) margin) (vz point) (- (vz high) margin))))))

(defun run-won-p ()
  "True once a run's boss is dead: nothing hurts the player any more. Not on the test level,
whose boss is only a try."
  (let ((boss (and (eq *level* :generated) *arena* (arena-boss *arena*))))
    (and boss (dead boss) T)))

(defun win-run ()
  "The boss is dead: the run is over, won. The world freezes and the victory screen comes up."
  (when (eq *game-state* :playing)
    (setf *game-state* :victory)
    (when *player* (release-mouse *player*))))

;;; Powers.

(defclass boss-power ()
  ((name :initarg :name :reader power-name)
   (label :initarg :label :reader power-label :documentation "What the boss bar calls it.")
   (passive :initarg :passive :initform NIL :reader power-passive-p
            :documentation "True for a power that is no attack, only a change while the boss has it.")
   (cooldown :initarg :cooldown :initform 8.0 :reader power-cooldown
             :documentation "Seconds before it can be used again, from when it lands.")
   (frame-times :initarg :frame-times :initform '(0.4 0.4 0.25 0.35) :reader power-frame-times
                :documentation "Seconds each frame of the boss's POWER-ANIMATION shows.")
   (hit-frame :initarg :hit-frame :initform 2 :reader power-hit-frame)
   (pause :initarg :pause :initform 0.8 :reader power-pause)
   (deny :initarg :deny :initform () :reader power-deny
         :documentation "The kinds (strings) and traits (:FLYER, :CASTER) it isn't given to.")
   (usable :initarg :usable :initform (constantly T) :reader power-usable
           :documentation "Function of the boss: true if it may start the power now.")
   (start :initarg :start :initform NIL :reader power-start
          :documentation "Function of the boss that starts it, true if it did; NIL to start it as an attack.")
   (release :initarg :release :initform (constantly NIL) :reader power-release
            :documentation "Function of the boss: what lands on the hit frame.")))

(defvar *boss-powers* (make-hash-table :test 'eq))

(defparameter *boss-power-names*
  '(:fire-volley :skull-barrage :grave-circle :leap :shockwave :tornado :summon :blink :warded :haste)
  "Every power, in the order a boss's are drawn from.")

(defmacro define-boss-power (name &body initargs)
  `(setf (gethash ,name *boss-powers*) (make-instance 'boss-power :name ,name ,@initargs)))

(defun find-power (name)
  (or (gethash name *boss-powers*) (error "No boss power ~s." name)))

(defun power-allowed-p (name kind)
  (let ((deny (power-deny (find-power name))))
    (not (or (member kind deny :test #'equalp)
             (intersection (sixth (boss-kind-entry kind)) deny)))))

(defun pick-boss-powers (kind random)
  "Three powers KIND may have, drawn from RANDOM, at most one of them passive."
  (let ((left (remove-if-not (lambda (name) (power-allowed-p name kind)) *boss-power-names*))
        (picked ()))
    (loop while (and left (< (length picked) 3))
          do (let ((name (nth (random (length left) random) left)))
               (setf left (remove name left))
               (unless (and (power-passive-p (find-power name)) (some (lambda (p) (power-passive-p (find-power p))) picked))
                 (push name picked))))
    (nreverse picked)))

(defun make-boss (at facing)
  "The boss for a spawn at AT facing FACING: its kind and powers drawn from *BLOCK-RANDOM*,
or *BOSS-OVERRIDE*'s."
  (destructuring-bind (kind &rest powers)
      (or *boss-override* (list (first (nth (random (length *boss-kinds*) *block-random*) *boss-kinds*))))
    (make-instance (second (boss-kind-entry kind)) :location at :facing facing :kind kind
                                                   :powers (or powers (pick-boss-powers kind *block-random*)))))

(defun boss-sees-player-p (boss range)
  (and (< (player-distance boss) range)
       (clear-path-p (location boss) (feet *player*) (cast-height boss))))

(defun cast-fan (boss spell count spread)
  "Cast COUNT of SPELL from in front of BOSS at the player, fanned over SPREAD radians."
  (let* ((loc (location boss))
         (feet (feet *player*))
         (out (+ (body-radius boss) 0.15))
         (yaw (facing boss))
         (origin (vec (+ (vx loc) (* out (sin yaw))) (+ (vy loc) (cast-height boss)) (- (vz loc) (* out (cos yaw)))))
         (aim (v- (vec (vx feet) (+ (vy feet) *cast-aim-height*) (vz feet)) origin)))
    (when (< 1f-4 (vlength aim))
      (nvunit aim)
      (dotimes (i count)
        (let* ((a (if (< 1 count) (* spread (- (/ i (1- count)) 0.5)) 0.0))
               (c (cos a)) (s (sin a)))
          (cast-spell (find-spell spell) (vcopy origin)
                      (vec (- (* c (vx aim)) (* s (vz aim))) (vy aim) (+ (* s (vx aim)) (* c (vz aim))))
                      (container boss) :caster boss))))))

(defun live-minions ()
  (count-if (lambda (c) (and (summoned c) (not (dead c)))) *creatures*))

(defun summon-spots (boss)
  "Where BOSS's minions will rise: two, three enraged, fanned out in front of it, each on the
floor a body of its kind fits, or fewer where none does."
  (let* ((class (third (boss-kind-entry (boss-kind boss))))
         (n (if (enraged boss) 3 2))
         (loc (location boss))
         (yaw (facing boss))
         (d (+ (body-radius boss) 1.5))
         ;; One of its kind, to measure the room a minion needs.
         (sample (make-instance class))
         (spots ()))
    (dotimes (i n (nreverse spots))
      ;; 1.3 rad apart: their sigils, 1.8 m across, don't touch.
      (let* ((a (+ yaw (* (- i (/ (1- n) 2.0)) 1.3)))
             (p (vec (+ (vx loc) (* d (sin a))) (vy loc) (- (vz loc) (* d (cos a))))))
        (multiple-value-bind (ci cj ck)
            (and *nav-grid* (nav-nearest-fitting p (body-radius sample) (sprite-height sample) :search 2))
          (when ci
            (push (nav-point ci cj ck) spots)))))))

(defun begin-summon (boss)
  "Start BOSS's Summon: a sigil draws itself on the floor at each spot a minion will rise
from, through the cast. True if there was room for any."
  (let ((spots (summon-spots boss)))
    (when spots
      (start-power-attack boss :summon)
      (dolist (at spots T)
        (enter (make-instance 'summon-sigil :caster boss :centre at :location (vcopy at)
                                            :animation (find-fx-animation 'summon-sigil))
               (container boss))))))

(defun summoning-p (boss)
  "True while BOSS's Summon has yet to be released, which is how long its sigils stay."
  (and boss
       (not (dead boss))
       (eq (boss-power boss) :summon)
       (winding-up-p boss)))

(defun summon-minions (boss)
  "Summon's release: from each of BOSS's sigils flame bursts up, and one of its kind, at its
normal size, gets up out of it."
  (let ((class (third (boss-kind-entry (boss-kind boss))))
        (sigils ()))
    (for:for ((entity over (container boss)))
      (when (and (typep entity 'summon-sigil) (eq (caster entity) boss) (not (burst entity)))
        (push entity sigils)))
    (dolist (sigil sigils)
      (let* ((at (centre sigil))
             (minion (make-instance class :location (vcopy at) :facing (facing boss) :summoned T)))
        (play-sound :summon-burst at)
        (setf (burst sigil) 0.0
              (rising minion) (death-duration minion)
              (alert minion) *alert-time*)
        (spawn-creature minion (container boss))
        (update-creature-look minion)))))

;;; The sigil, flat on the floor; at the release, a column of flame stands up on it.

(defparameter *sigil-burst-time* 1.1 "Seconds the flame takes to rise, flare and die away.")
(defparameter *sigil-flame-height* '(0.6 3.0) "Metres the flame stands at the burst and at its tallest.")
(defparameter *sigil-flame-radius* 0.55 "Metres across from its middle that the flame stands.")
(defparameter *sigil-light-color* (vec 2.0 0.75 0.2) "Its lamp at full strength, just before the burst.")
(defparameter *sigil-light-radius* 4.0)
(defparameter *sigil-flash* 2.0 "How much brighter the lamp flares at the burst.")
(defparameter *sigil-flame-colors*
  (list (vec 1.0 0.45 0.08) (vec 1.0 0.7 0.2) (vec 0.95 0.25 0.05) (vec 0.6 0.1 0.03) (vec 1.0 0.85 0.5))
  "The flame, as *GRAVE-AURORA-COLORS*: fire. Read when it bursts.")

(define-fx-animation summon-sigil "sprites/summon/sigil" :loop T :size (/ 139 64.0))

(define-shader-entity summon-sigil (fx-sprite)
  ((caster :initarg :caster :initform NIL :reader caster)
   (centre :initarg :centre :reader centre)
   (burst :initform NIL :accessor burst :documentation "Seconds since the flame burst up, or NIL.")
   (lamp :initform NIL :accessor sigil-lamp)
   (flame :initform NIL :accessor sigil-flame)
   (sound :initform NIL :accessor sigil-sound :documentation "Its loop through the cast, or NIL.")))

(defmethod initialize-instance :after ((sigil summon-sigil) &key)
  ;; Flat on the floor, facing up, just off it.
  (!qfrom-angle (orientation sigil) +vx+ #.(float (- (/ pi 2)) 0f0))
  (incf (vy (location sigil)) 0.01))

(defmethod leave :after ((sigil summon-sigil) container)
  (setf (sigil-sound sigil) (stop-loop (sigil-sound sigil)))
  (when (sigil-flame sigil)
    (despawn (sigil-flame sigil))
    (setf (sigil-flame sigil) NIL))
  (when (sigil-lamp sigil)
    (remove-lamp (sigil-lamp sigil))
    (setf (sigil-lamp sigil) NIL)))

(defun sigil-strength (sigil)
  "How bright SIGIL's lamp is: rising through the cast, flaring at the burst, then dying."
  (let ((burst (burst sigil)))
    (if burst
        (* (+ 1 *sigil-flash*) (max 0.0 (- 1 (/ burst *sigil-burst-time*))))
        (min 1.0 (/ (age sigil) (max 0.1 (power-hit-time :summon)))))))

(defun power-hit-time (name)
  (let ((power (find-power name)))
    (loop for time in (power-frame-times power)
          repeat (power-hit-frame power)
          sum time)))

;; Its own tick, not FX-SPRITE's: the frame follows the cast, and it lies flat.
(define-handler (summon-sigil tick) (dt)
  (let ((c (centre summon-sigil)))
    (when (and (null (sigil-lamp summon-sigil)) (container summon-sigil))
      (setf (sigil-lamp summon-sigil)
            (add-lamp (vec (vx c) (+ (vy c) 0.6) (vz c)) (vec 0 0 0) *sigil-light-radius* :flicker 0.2)))
    (when (and (burst summon-sigil) (null (sigil-flame summon-sigil)) (container summon-sigil))
      (setf (sigil-flame summon-sigil)
            (make-instance 'aurora :centre (vcopy c) :radius *sigil-flame-radius*
                                   :colors *sigil-flame-colors* :spin 0.6 :twist 0.35))
      (enter (sigil-flame summon-sigil) (container summon-sigil)))
    (setf (sigil-sound summon-sigil)
          (hold-loop (sigil-sound summon-sigil)
                     (and (container summon-sigil) (not (burst summon-sigil)) :summon-sigil) c))
    (unless (frozen-p)
      (incf (age summon-sigil) dt)
      (cond ((burst summon-sigil)
             (when (< *sigil-burst-time* (incf (burst summon-sigil) dt))
               (despawn summon-sigil)))
            ;; A broken cast takes its sigils with it.
            ((not (summoning-p (caster summon-sigil)))
             (despawn summon-sigil))))
    (let* ((atlas (animation-atlas (sprite-animation summon-sigil)))
           (count (getf atlas :frames))
           (k (sigil-strength summon-sigil))
           (lamp (sigil-lamp summon-sigil))
           (flame (sigil-flame summon-sigil))
           (burst (burst summon-sigil)))
      (strip-uv (frame-uv summon-sigil) atlas (sign-frame (age summon-sigil) (power-hit-time :summon) count) count)
      (when lamp
        (let ((color (color lamp)))
          (setf (vx color) (* k (vx *sigil-light-color*))
                (vy color) (* k (vy *sigil-light-color*))
                (vz color) (* k (vz *sigil-light-color*)))))
      (when (and flame burst)
        ;; Up fast and tall, then guttering out.
        (let ((u (/ burst *sigil-burst-time*)))
          (destructuring-bind (low high) *sigil-flame-height*
            (setf (aurora-height flame) (+ low (* (- high low) (min 1.0 (* 4.0 u))))
                  (aurora-strength flame) (* (min 1.0 (* 8.0 u)) (- 1.0 (* u u))))))))))

(defun blink-destination (boss)
  "Where BOSS's Blink takes it: a ranged kind 9 m from the player on its own side of them, a
melee kind right behind them. A cell its body fits in the arena, in sight of the player, or NIL."
  (let* ((feet (feet *player*))
         (loc (location boss))
         (r (body-radius boss))
         (h (sprite-height boss))
         (ranged (ranged-p boss))
         (base (if ranged
                   (atan (- (vx loc) (vx feet)) (- (vz feet) (vz loc)))
                   (+ (vy (rotation *player*)) pi)))
         (d (if ranged 9.0 (+ r *player-radius* 1.0))))
    (loop for turn in '(0.0 0.7 -0.7 1.4 -1.4 2.2 -2.2)
          for yaw = (+ base turn)
          for p = (vec (+ (vx feet) (* d (sin yaw))) (vy feet) (- (vz feet) (* d (cos yaw))))
          do (multiple-value-bind (i j k) (and *nav-grid* (nav-nearest-fitting p r h :search 2))
               (when i
                 (let ((to (nav-point i j k)))
                   (when (and (arena-contains-p to (+ r 0.5))
                              (clear-path-p to feet 1.0)
                              (not (body-overlapping (vx to) (+ (vy to) 0.05) (vz to) (float r 0f0) (- (float h 0f0) 0.05) boss)))
                     (return to))))))))

(defun blink (boss)
  (let ((to (blink-destination boss))
        (loc (location boss)))
    (when to
      (spawn-fx 'bolt-burst (vec (vx loc) (+ (vy loc) (* 0.5 (sprite-height boss))) (vz loc)) (container boss))
      (play-sound :blink-out loc)
      (play-sound :blink-in to)
      (v<- loc to)
      (let ((kb (momentum boss))) (setf (vx kb) 0.0 (vz kb) 0.0))
      (setf (path boss) ())
      (face-player boss)
      (spawn-fx 'bolt-burst (vec (vx to) (+ (vy to) (* 0.5 (sprite-height boss))) (vz to)) (container boss)))))

(define-boss-power :fire-volley
  :label "Fire volley" :cooldown 6.0 :frame-times '(0.4 0.3 0.25 0.35)
  :usable (lambda (boss) (boss-sees-player-p boss 14.0))
  :release (lambda (boss) (cast-fan boss 'cinder 5 0.6)))

(define-boss-power :skull-barrage
  :label "Skull barrage" :cooldown 8.0 :frame-times '(0.45 0.3 0.25 0.35)
  :usable (lambda (boss) (boss-sees-player-p boss 16.0))
  :release (lambda (boss) (cast-fan boss 'grave-skull 3 0.8)))

(define-boss-power :grave-circle
  :label "Grave circle" :cooldown 12.0 :frame-times '(0.35 0.4 0.25 0.35) :deny '("necromancer")
  :usable (lambda (boss) (and (boss-sees-player-p boss 12.0) (not (swimming *player*))))
  :release (lambda (boss)
             (cast-spell (find-spell 'grave-spikes) (floor-under (feet *player*)) (vec 0 0 -1) (container boss)
                         :caster boss)))

;; The ogre's leap (ogre.lisp), on its own cooldown, LEAP-COOLDOWN.
(define-boss-power :leap
  :label "Leap" :deny '(:flyer :caster "ogre")
  :usable (lambda (boss) (typep boss 'leaper))
  :start #'try-leap)

(define-boss-power :shockwave
  :label "Shockwave" :cooldown 9.0 :frame-times '(0.9 0.15 0.2 0.5) :pause 1.0 :deny '(:flyer)
  :usable (lambda (boss) (< (player-distance boss) (+ (body-radius boss) 3.5)))
  :release (lambda (boss)
             (let ((at (location boss)))
               (play-sound :ogre-land at)
               (quake boss at *boss-quake-radius* *boss-quake-damage* *quake-shove* *quake-player-shove*
                      *quake-player-lift* :inner (body-radius boss))
               (kick-dust at (* 0.6 *boss-quake-radius*) *ogre-dust-puffs* (container boss))
               (hit-stop *leap-hit-stop*))))

;; The wraith's tornado: the sign is drawn under the player when the cast begins, and the
;; tornado forms on it at the release (wraith.lisp). Only one of its own up at a time.
(define-boss-power :tornado
  :label "Tornado" :cooldown 16.0 :frame-times '(0.3 1.2 0.25 0.35) :pause 1.0 :deny '("gale-wraith")
  :usable (lambda (boss)
            (and (boss-sees-player-p boss 14.0) (not (own-vortex boss))
                 (not (swimming *player*)) (not (whirl *player*))))
  :start (lambda (boss)
           (let ((point (power-point boss)))
             (v<- point (floor-under (feet *player*)))
             (start-power-attack boss :tornado)
             (enter (make-instance 'gale-sign :caster boss :centre (vcopy point) :location (vcopy point)
                                              :animation (find-fx-animation 'gale-sign))
                    (container boss))
             T))
  :release (lambda (boss)
             (cast-spell (find-spell 'tempest) (power-point boss) (vec 0 0 -1) (container boss) :caster boss)))

(define-boss-power :summon
  :label "Summoner" :cooldown 15.0 :frame-times '(0.4 0.7 0.25 0.35) :pause 1.0
  :usable (lambda (boss) (declare (ignore boss)) (< (live-minions) *boss-max-minions*))
  :start #'begin-summon
  :release #'summon-minions)

(define-boss-power :blink
  :label "Blink" :cooldown 10.0 :frame-times '(0.35 0.1 0.15 0.25) :hit-frame 1 :pause 0.4
  :usable (lambda (boss)
            (if (ranged-p boss)
                (< (player-distance boss) 4.0)
                (< 9.0 (player-distance boss))))
  :release #'blink)

(define-boss-power :warded
  :label "Warded" :passive T :deny '("knight"))

(define-boss-power :haste
  :label "Haste" :passive T)

;;; The boss.

(define-shader-entity boss ()
  ((kind :initarg :kind :reader boss-kind :documentation "Its kind, as in *BOSS-KINDS*.")
   (powers :initarg :powers :initform () :accessor boss-powers
           :documentation "Its three powers' names; the third comes in when it enrages.")
   (dormant :initform T :accessor dormant :documentation "True until its arena is sealed.")
   (enraged :initform NIL :accessor enraged)
   (boss-power :initform NIL :accessor boss-power :documentation "The power its attack is, or NIL for its own.")
   (power-cooldowns :initform () :accessor power-cooldowns :documentation "Seconds left on each power, by name.")
   (power-gap :initform 0.0 :accessor power-gap :documentation "Seconds before it may start another power.")
   (power-point :initform (vec 0 0 0) :reader power-point :documentation "Where its tornado will form.")
   (roar :initform 0.0 :accessor roar :documentation "Seconds left of its enraged roar.")
   (glow :initform (vec4 0 0 0 0) :reader glow :documentation "The rim's colour and strength this frame.")
   (texel :initform (vec2 0 0) :reader texel)
   (glow-lamp :initform NIL :accessor glow-lamp)
   (ward :initform NIL :accessor ward :documentation "The AURORA arc that shows Warded, once it has it.")
   (ward-sound :initform NIL :accessor ward-sound :documentation "The ward's hum while it is up, or NIL."))
  (:documentation "The run's boss: an empowered monster. List it first in the superclasses."))

(defmethod initialize-instance :after ((boss boss) &key)
  (destructuring-bind (kind class base title scale traits) (boss-kind-entry (boss-kind boss))
    (declare (ignore kind class base title))
    (let ((k (float scale 0f0)))
      ;; The billboard and the creature have already sized it from its kind's height.
      (setf (sprite-height boss) (* k (sprite-height boss))
            (slot-value boss 'size-scale) k)
      (nv* (scaling boss) k)
      (nv* (base-scaling boss) k)
      (setf (body-radius boss) (min *boss-max-radius* (* k (body-radius boss)))
            (attack-reach boss) (* k (attack-reach boss))
            (cast-offset boss) (* k (cast-offset boss))
            (knockback-scale boss) (min *boss-max-knockback* (knockback-scale boss))
            (max-health boss) *boss-health*
            (health boss) *boss-health*
            (slot-value boss 'pain-chance) *boss-pain-chance*
            ;; Its death always plays: no blow tears it apart.
            (slot-value boss 'gib-overkill) 100.0)
      (when (< *nav-clearance-height* (sprite-height boss))
        (setf (step-height boss) (max (step-height boss) *nav-tall-lift*)))
      (when (attack-damage boss)
        (setf (attack-damage boss) (mapcar (lambda (d) (round (* d *boss-damage-scale*))) (attack-damage boss))))
      (when (member :flyer traits)
        (setf (hover-height boss) (min (hover-height boss) *boss-hover*)))))
  (reset-boss boss))

(defun reset-boss (boss)
  "BOSS as it waits for the player: asleep, calm, every power ready."
  (setf (dormant boss) T
        (enraged boss) NIL
        (boss-power boss) NIL
        (power-gap boss) 0.0
        (roar boss) 0.0
        (power-cooldowns boss) (loop for name in (boss-powers boss) collect name collect 0.0)))

(defmethod dormant-p ((boss boss)) (and (dormant boss) (not (dead boss))))

;; On the test level a dead boss stays dead: a reset brings another.
(defmethod stays-dead-p ((boss boss)) T)

(defun boss-title (boss) (fourth (boss-kind-entry (boss-kind boss))))

(defun active-powers (boss)
  "The powers BOSS has now: the first two, and the third once it is enraged."
  (if (enraged boss) (boss-powers boss) (subseq (boss-powers boss) 0 (min 2 (length (boss-powers boss))))))

(defun has-power-p (boss name)
  (member name (active-powers boss)))

(defun attack-speed (boss)
  (* (if (has-power-p boss :haste) *haste-speed* 1.0) (if (enraged boss) *boss-enrage-attack-speed* 1.0)))

(defun move-speed (boss)
  (* (if (has-power-p boss :haste) *haste-speed* 1.0) (if (enraged boss) *boss-enrage-speed* 1.0)))

;; Warded: its front turns spells back, as the knight's shield does.
(defmethod shield-views ((boss boss))
  (if (has-power-p boss :warded) (max 1 (or (call-next-method) 0)) (call-next-method)))

(defmethod walk-speed ((boss boss)) (* (move-speed boss) (call-next-method)))

(defmethod chase-speed ((boss boss))
  (let ((speed (call-next-method)))
    (and speed (* (move-speed boss) speed))))

(defun current-power (boss)
  (let ((name (boss-power boss)))
    (and name (find-power name))))

(defmethod attack-frame-times ((boss boss))
  (let ((power (current-power boss)))
    (if power (power-frame-times power) (call-next-method))))

(defmethod attack-hit-frame ((boss boss))
  (let ((power (current-power boss)))
    (if power (power-hit-frame power) (call-next-method))))

(defmethod attack-pause ((boss boss))
  (let ((power (current-power boss)))
    (* (if (enraged boss) *boss-enrage-pause* 1.0)
       (if power (power-pause power) (call-next-method)))))

(defgeneric power-animation (boss)
  (:documentation "The strip, four frames per view, a power's attack shows: its kind's attack or cast.")
  (:method ((boss boss)) (slot-value boss 'attack-animation)))

(defmethod attack-animation ((boss boss))
  (if (boss-power boss) (power-animation boss) (call-next-method)))

(defmethod face-attack-target ((boss boss) dt)
  (if (boss-power boss) (face-player boss dt) (call-next-method)))

;; Its attacks run faster with Haste and enraged; a power's runs as a plain attack, a flyer's
;; too (a cast in place, as the wraith's).
(defmethod attack-step ((boss boss) dt)
  (let ((dt (* dt (attack-speed boss))))
    (if (boss-power boss) (attack boss dt) (call-next-method boss dt))))

(defmethod release-attack ((boss boss))
  (let ((power (current-power boss)))
    (cond (power
           (funcall (power-release power) boss)
           (setf (getf (power-cooldowns boss) (power-name power))
                 (* (power-cooldown power) (if (enraged boss) *boss-enrage-cooldown* 1.0))))
          (T (call-next-method)))))

(defun start-power-attack (boss name)
  (setf (boss-power boss) name
        (power-gap boss) *boss-power-gap*)
  (start-attack boss))

(defmethod special-attack ((boss boss))
  (setf (boss-power boss) NIL)
  (or (and (<= (power-gap boss) 0)
           (loop for name in (active-powers boss)
                 for power = (find-power name)
                 thereis (and (not (power-passive-p power))
                              (<= (getf (power-cooldowns boss) name 0.0) 0)
                              (funcall (power-usable power) boss)
                              (if (power-start power)
                                  (when (funcall (power-start power) boss)
                                    (setf (power-gap boss) *boss-power-gap*)
                                    T)
                                  (progn (start-power-attack boss name) T)))))
      (call-next-method)))

(defmethod casting-tempest-p ((boss boss))
  (or (and (eq (boss-power boss) :tornado) (not (dead boss)) (winding-up-p boss))
      (call-next-method)))

;; Big and heavy: no tornado lifts it, its own or the player's.
(defmethod vortex-proof-p ((boss boss)) T)

(defun enrage (boss)
  (setf (enraged boss) T
        (roar boss) *boss-roar-time*
        (power-gap boss) 0.0)
  (stop-walking boss *boss-roar-time*)
  (play-sound :boss-enrage (location boss))
  (kick-dust (location boss) (* 0.6 *boss-quake-radius*) *ogre-dust-puffs* (container boss))
  (hit-stop 0.3))

(defun update-boss-glow (boss)
  "The rim, the lamp and Warded's arc: dim asleep, pulsing awake, flaring as it roars, going out as it dies."
  (let* ((d (dead boss))
         (k (cond (d (max 0.0 (- 1.0 (/ d (max 0.1 (death-duration boss))))))
                  ((dormant boss) 0.4)
                  (T 1.0)))
         (pulse (+ 0.75 (* 0.25 (sin (* (if (enraged boss) 7.0 3.5) *light-clock*)))))
         (strength (* k (min 1.0 (+ pulse (* 1.5 (roar boss))))))
         (glow (glow boss)))
    (setf (vx glow) (vx *boss-glow-color*) (vy glow) (vy *boss-glow-color*) (vz glow) (vz *boss-glow-color*)
          (vw glow) strength)
    (let ((lamp (glow-lamp boss)))
      (when (and (container boss) (not (and lamp (find lamp *lamps*))))
        (setf lamp (add-lamp (location boss) (vcopy *boss-glow-color*) *boss-light-radius* :flicker 0.1 :source boss)
              (glow-lamp boss) lamp))
      (when lamp
        (let ((color (color lamp)))
          (setf (vx color) (* strength (vx *boss-glow-color*))
                (vy color) (* strength (vy *boss-glow-color*))
                (vz color) (* strength (vz *boss-glow-color*))))))
    (update-ward boss k)))

(defun ward-arc (boss)
  "Radians either side of BOSS's facing that its Warded front turns spells back from: the
billboard views its SHIELD-VIEWS covers (SHIELDED-P), each a quarter of pi wide."
  (* (+ (shield-views boss) 0.5) (/ pi 4)))

(defun update-ward (boss k)
  "Show Warded as a violet curtain of light on the floor round BOSS's front, over the sector
its reflection covers, turning with it; K dims it as the rim is dimmed."
  (let ((ward (ward boss)))
    (when (and (null ward) (container boss) (has-power-p boss :warded) (not (dead boss)))
      (setf ward (make-instance 'aurora :centre (vcopy (location boss)) :radius (+ (body-radius boss) *ward-reach*)
                                        :colors *ward-colors* :spin 0.15 :twist 0.05 :arc (ward-arc boss))
            (ward boss) ward)
      (enter ward (container boss)))
    (setf (ward-sound boss)
          (hold-loop (ward-sound boss)
                     (and ward (container boss) (has-power-p boss :warded) (not (dead boss)) :ward-hum)
                     (location boss) k))
    (when ward
      (let* ((loc (location boss))
             (floor (and *nav-grid* (nav-floor-at (vx loc) (vy loc) (vz loc))))
             (centre (centre ward)))
        (setf (vx centre) (vx loc) (vy centre) (float (or floor (vy loc)) 0f0) (vz centre) (vz loc)
              ;; Round the ring from +X toward +Z: the facing's (sin, -cos) is a quarter turn back.
              (aurora-arc-middle ward) (float (- (facing boss) (/ pi 2)) 0f0)
              (aurora-height ward) *ward-height*
              (aurora-strength ward) (if (has-power-p boss :warded) (* *ward-strength* k) 0.0))))))

(defmethod leave :after ((boss boss) container)
  (setf (ward-sound boss) (stop-loop (ward-sound boss)))
  (when (ward boss)
    (despawn (ward boss))
    (setf (ward boss) NIL)))

(define-handler (boss tick :after) (dt)
  (let ((arena *arena*))
    (unless (frozen-p)
      (let ((dt (min dt 0.05)))
        (setf (roar boss) (max 0.0 (- (roar boss) dt)))
        (cond ((dead boss)
               ;; Its summons die with it.
               (loop for c across *creatures*
                     do (when (and (summoned c) (not (dead c)))
                          (burn c (health c))))
               (when (and (eq *game-state* :playing) (< (+ (death-duration boss) *victory-delay*) (dead boss)))
                 (if (eq *level* :generated)
                     (win-run)
                     ;; Elsewhere (the test level) there is no run to win: the gate goes up
                     ;; again, so the player can leave.
                     (when (and arena (sealed arena))
                       (play-sound :gate-rise (connector-location (arena-door arena)))
                       (unseal-arena)))))
              ((dormant boss)
               (when (and arena (eq (arena-boss arena) boss) *player* (< 0 (health *player*))
                          (player-in-arena-p arena *arena-trigger-depth*))
                 (seal-arena)))
              (T
               (setf (alert boss) (max (alert boss) *alert-time*)
                     (power-gap boss) (max 0.0 (- (power-gap boss) dt)))
               (loop for (name left) on (power-cooldowns boss) by #'cddr
                     do (setf (getf (power-cooldowns boss) name) (max 0.0 (- left dt))))
               (unless (eq (brain boss) :attacking)
                 (setf (boss-power boss) NIL))
               (when (and (not (enraged boss)) (<= (health boss) (* *boss-enrage-at* (max-health boss))))
                 (enrage boss)))))
      (when (and arena (sealed arena) (< (gate-drop arena) 1.0))
        (setf (gate-drop arena) (min 1.0 (+ (gate-drop arena) (/ dt *gate-drop-time*))))
        (place-gate arena)))
    (update-boss-glow boss)))

;;; Its look: a warm cast over the whole body and a pulsing rim, one art pixel wide, round
;;; its silhouette. On the boss's program only.

(defmethod render :before ((boss boss) (program shader-program))
  (let ((texture (texture boss))
        (texel (texel boss)))
    (setf (vx texel) (/ 1.0 (width texture)) (vy texel) (/ 1.0 (height texture)))
    (setf (uniform program "boss_glow") (glow boss))
    (setf (uniform program "boss_texel") texel)
    (setf (uniform program "boss_shade") *boss-shade*)))

(define-class-shader (boss :fragment-shader)
  "in vec2 uv;
out vec4 color;
uniform sampler2D texture_image;
uniform vec4 boss_glow;
uniform vec2 boss_texel;
uniform vec3 boss_shade;

void main(){
  maybe_call_next_method();
  // An opaque texel with a see-through one beside it is on the rim.
  float rim = 0.0;
  rim = max(rim, step(texture(texture_image, uv + vec2(boss_texel.x, 0.0)).a, 0.5));
  rim = max(rim, step(texture(texture_image, uv - vec2(boss_texel.x, 0.0)).a, 0.5));
  rim = max(rim, step(texture(texture_image, uv + vec2(0.0, boss_texel.y)).a, 0.5));
  rim = max(rim, step(texture(texture_image, uv - vec2(0.0, boss_texel.y)).a, 0.5));
  color.rgb = mix(color.rgb * boss_shade, boss_glow.rgb, rim * boss_glow.a);
}")

;;; One class per kind.

(define-shader-entity imp-boss (boss leaper imp) ())
(define-shader-entity acolyte-boss (boss acolyte) ())
(define-shader-entity knight-boss (boss leaper knight) ())
(define-shader-entity harpy-boss (boss harpy) ())
(define-shader-entity necromancer-boss (boss necromancer) ())
(define-shader-entity ogre-boss (boss ogre) ())
(define-shader-entity wraith-boss (boss gale-wraith) ())

(defmethod power-animation ((boss harpy-boss)) (flap-animation boss))
(defmethod power-animation ((boss necromancer-boss)) 'necromancer-cast)
(defmethod power-animation ((boss wraith-boss)) 'wraith-cast)
