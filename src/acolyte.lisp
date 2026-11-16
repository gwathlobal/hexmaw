(in-package #:hexmaw)

;;; The acolyte: a robed caster that keeps its distance and throws cinders (spells.lisp). It
;;; has no walk: it glides in the standing pose, the robe hiding its feet.
;;;
;;; From the second level of a run on (LEVEL-ABILITY-P, run.lisp), and on the debug level, it
;;; also calls down a firestorm. A sun wheel of fire draws itself on the floor under the player
;;; while the acolyte holds its fireball up; then the storm comes down on it, and burns as long
;;; as the acolyte holds its hand out, drifting after the player. Absorb (magic.lisp) takes only
;;; projectiles, so a player who stood swallowing its cinders for mana has to walk out, and
;;; walking with Absorb held is slower than the storm. A flinch or its death puts the storm out.

(defparameter *acolyte-height* 1.8 "Acolyte height in metres, cowl tip to hem.")

(defparameter *firestorm-telegraph* 1.6
  "Seconds from the start of its cast to the storm coming down: the sign drawing itself in, the
time to step out of it.")
(defparameter *firestorm-time* 8.0 "Seconds the storm burns while the acolyte holds it.")
(defparameter *firestorm-fade* 1.0 "Seconds the storm takes to die down once it is no longer held.")
(defparameter *firestorm-cooldown* 16.0 "Seconds from one storm coming down to the next cast.")
(defparameter *firestorm-retry* 4.0 "Seconds before it tries again after a broken cast.")
(defparameter *firestorm-first* 4.0 "Seconds of cooldown an acolyte starts with, so a fight opens with cinders.")
(defparameter *firestorm-range* 10.0 "Metres from the acolyte its target may be for a storm.")
(defparameter *firestorm-swallow-trigger* 2
  "Cinders of its that the player's Absorb swallows (NOTE-ABSORBED) after which its next storm comes at once.")
(defparameter *firestorm-chance* 30
  "Percent chance it calls a storm that is ready when nothing provokes one, each time it would
throw a cinder.")
(defparameter *firestorm-pulse* 0.5 "Seconds between the storm's burns.")
(defparameter *firestorm-afterburn* '(2 2.0)
  "Damage a second, and seconds, of the burn each of the storm's burns leaves on what it strikes.")
(defparameter *firestorm-drift* 2.5
  "M/s the storm drifts after its target: less than a walk, more than a walk holding Absorb.")
(defparameter *firestorm-pain-bonus* 20 "Percent added to the acolyte's pain chance while it holds a storm.")
(defparameter *firestorm-light-color* (vec 1.8 0.7 0.25) "Its lamp's colour at full strength.")
(defparameter *firestorm-light-radius* 7.0)
(defparameter *firestorm-flash* 1.5 "How much brighter the lamp flashes as the storm comes down.")
(defparameter *firestorm-flash-time* 0.4)
(defparameter *firestorm-aurora-colors*
  (mapcar #'nova-hex '("fb6403" "fcb918" "fe901f" "ac0f07" "fceab6"))
  "The colours of the aurora round its rim, as *GRAVE-AURORA-COLORS*: the fire nova's.")
(defparameter *firestorm-aurora-spin* 0.15 "Turns a second its aurora's streaks run round. Read when a storm is lit.")
(defparameter *firestorm-aurora-twist* 0.1 "Whole turns they lean, foot to top. Read when a storm is lit.")
(defparameter *firestorm-cinders* 5.0 "Cinders a second falling on the storm.")
(defparameter *firestorm-cinder-height* 4.0 "Metres over the floor they fall from, or from under the ceiling.")
(defparameter *firestorm-cinder-speed* 9.0 "M/s they fall at.")
(defparameter *firestorm-cinder-sparks* 6 "Sparks each throws as it strikes the floor.")
(defparameter *firestorm-embers* 8.0 "Embers a second rising round its rim.")

;; Sliced at 115 px tall, so its art pixels are the imp's size (96 px for 1.5 m).
(define-asset (hexmaw acolyte-turnaround) image
    #p"sprites/acolyte/turnaround.png"
  :min-filter :nearest :mag-filter :nearest)

;; The cast: wind-up (a flame kindles in the hand), raised hand (a fireball held beside
;; the cowl), release, recover; four frames per view. Its cells are 125 px tall to fit
;; the fire, with the standing acolyte 115 px like the turnaround. The frames run on
;; ATTACK-FRAME-TIMES, so :FPS is unused. The firestorm holds the raised hand through the
;; sign's draw-in and the release through the storm.
(define-fx-animation acolyte-cast "sprites/acolyte/cast" :size (* *acolyte-height* 125/115))
;; The flinch: jolt, then stagger, two frames per view over *STAGGER-TIME*. Its cells
;; are 116 px tall, at the turnaround's scale.
(define-fx-animation acolyte-hurt "sprites/acolyte/hurt" :size (* *acolyte-height* 116/115))
;; The fire inside burns it away, leaving the empty robe as the corpse. Its cells are
;; 133 px tall to fit the flames, the jolted acolyte in frame 1 115 px.
(define-fx-animation acolyte-death "sprites/acolyte/death" :fps 10 :size (* *acolyte-height* 133/115))

;; The sign: a sun wheel for a 2.5 m radius (tools/draw_fire_sign.py), its cell 348 px at 64 px
;; a metre, tongues of flame round it.
(define-fx-animation firestorm-sign "sprites/firestorm/sign" :loop T :size (/ 348 64.0))

;; What the storm burns with: its magnitude a burn, its area the sign's radius. The acolyte lays
;; the storm itself (BEGIN-FIRESTORM); the spell is its data, its sounds and its preloading.
(define-spell firestorm (:delivery :circle :windup *firestorm-telegraph* :title "Firestorm"
                         :circle-animation 'firestorm-sign
                         :light-color *firestorm-light-color* :light-radius *firestorm-light-radius*)
  (:damage :magnitude '(3 4) :area 2.5 :element :fire))

(defun acolyte-abilities ()
  (list (make-instance 'ability :name :cinder :spell 'cinder :animation 'acolyte-cast
                                ;; The fireball is held up longest, as the warning; it leaves on the release frame.
                                :frame-times '(0.3 0.25 0.3 0.3) :hit-frame 2 :pause 1.2)
        ;; The raised hand held while the sign draws in, the release held while the storm burns.
        (make-instance 'ability :name :firestorm :animation 'acolyte-cast
                                :frame-times (list 0.35 (- *firestorm-telegraph* 0.35) *firestorm-time* 0.4)
                                :hit-frame 2 :pause 1.2 :cooldown *firestorm-cooldown*)))

(define-shader-entity acolyte (ability-user creature)
  ((texture :initform (// 'hexmaw 'acolyte-turnaround))
   (atlas :initform (read-atlas "sprites/acolyte/turnaround.lisp"))
   (sprite-height :initform *acolyte-height*)
   ;; What a boss's powers show (POWER-ANIMATION, boss.lisp); the abilities answer otherwise.
   (attack-animation :initform 'acolyte-cast)
   (hurt-animation :initform 'acolyte-hurt)
   (death-animation :initform 'acolyte-death)
   ;; Up with the fire bursting out (frame 2), fading as the robe burns down (frames 5 to 8).
   (death-glow :initform (vec 1.4 0.55 0.2))
   ;; It burns from inside rather than bleeding out.
   (death-blood :initform 0)
   (abilities :initform (acolyte-abilities))
   (cooldowns :initform (list :firestorm *firestorm-first*))
   (swallowed :initform 0 :accessor swallowed
              :documentation "Its cinders the player's Absorb has swallowed since its last storm.")
   (storm :initform NIL :accessor acolyte-storm :documentation "Its firestorm while one is up.")
   (attack-range :initform 12.0)
   (keep-away :initform 4.0)
   (cast-offset :initform 0.25)
   (walk-speed :initform 1.2)
   (chase-speed :initform 1.8)
   (wander-radius :initform 2.0)
   (pain-chance :initform 25)
   (max-health :initform 24)))

(define-creature-sounds acolyte
  :alert :acolyte-alert :pain :acolyte-pain :death :acolyte-death :windup :acolyte-cast)

(defmethod note-absorbed ((acolyte acolyte) projectile)
  (incf (swallowed acolyte)))

(defun ability-p (creature name)
  (and (current-ability creature) (eq name (ability-name (current-ability creature)))))

(defun casting-firestorm-p (acolyte)
  "True while ACOLYTE's firestorm has yet to come down: the sign's draw-in."
  (and acolyte (not (dead acolyte)) (ability-p acolyte :firestorm) (winding-up-p acolyte)))

(defun storming-p (acolyte)
  "True while ACOLYTE holds its firestorm: past the release, within the frame held for it."
  (and acolyte (not (dead acolyte))
       (eq (brain acolyte) :attacking)
       (ability-p acolyte :firestorm)
       (not (attack-pending acolyte))
       (let ((time (attack-time acolyte))
             (hit (attack-hit-time acolyte)))
         (and time (<= hit time) (< time (+ hit (third (attack-frame-times acolyte))))))))

;; Holding the storm, it is easier to break.
(defmethod pain-chance :around ((acolyte acolyte))
  (if (storming-p acolyte)
      (+ (call-next-method) *firestorm-pain-bonus*)
      (call-next-method)))

(defun absorbing-at-p (acolyte target)
  "True if TARGET is the player holding Absorb with ACOLYTE in front of them, where it swallows."
  (and (eq target *player*)
       (channel target) (absorb-spell-p (channel target))
       (facing-point-p target (location acolyte) *block-arc*)))

(defun firestorm-ready-p (acolyte target)
  "True if ACOLYTE may call a firestorm on TARGET now: the level allows it, it is off cooldown,
none of its own is up, and TARGET stands on a floor, neither swimming nor whirled."
  (and (level-ability-p :firestorm)
       (ready-p acolyte :firestorm)
       (null (acolyte-storm acolyte))
       (not (target-swimming-p target))
       (not (whirl target))
       *nav-grid*
       (let ((feet (body-feet target)))
         (nav-floor-at (vx feet) (vy feet) (vz feet)))))

(defun wants-firestorm-p (acolyte target)
  "True if ACOLYTE calls its firestorm rather than a cinder: TARGET swallows its cinders, or a roll."
  (or (absorbing-at-p acolyte target)
      (<= *firestorm-swallow-trigger* (swallowed acolyte))
      (< (random 100 *roll-random*) *firestorm-chance*)))

(defmethod hunt-from-range ((acolyte acolyte))
  "Back off from a target too close; with one in range and sight, call a firestorm on it if it
may and wants to, else throw a cinder; or close in."
  (let* ((distance (target-distance acolyte))
         (target (hunt-target acolyte))
         (seen (and (< distance (attack-range acolyte))
                    (clear-path-p (location acolyte) (body-feet target) (cast-height acolyte)))))
    (cond ((and (< distance (keep-away acolyte)) (retreat acolyte)))
          ((and seen (< distance *firestorm-range*)
                (firestorm-ready-p acolyte target) (wants-firestorm-p acolyte target))
           (begin-firestorm acolyte))
          (seen (start-ability acolyte :cinder))
          (T (chase acolyte)))))

(defun begin-firestorm (acolyte)
  "Start casting the firestorm at the floor under what ACOLYTE hunts, marked there by its sign."
  (let* ((target (hunt-target acolyte))
         (point (floor-under (body-feet target)))
         (storm (make-instance 'firestorm :spell (find-spell 'firestorm) :caster acolyte :target target
                                          :centre point :location (vcopy point)
                                          :animation (find-fx-animation 'firestorm-sign))))
    (setf (getf (cooldowns acolyte) :firestorm) *firestorm-retry*)
    (start-ability acolyte :firestorm)
    (setf (acolyte-storm acolyte) storm)
    (enter storm (container acolyte))))

(defmethod release-attack ((acolyte acolyte))
  (let ((ability (current-ability acolyte)))
    (ecase (ability-name ability)
      (:cinder (release-attack-spell acolyte))
      (:firestorm
       (let ((storm (acolyte-storm acolyte)))
         (when (and storm (container storm))
           (ignite-firestorm storm)))
       (setf (swallowed acolyte) 0
             (getf (cooldowns acolyte) :firestorm) (* (ability-cooldown ability) (depth-scale :cooldown)))))))

(define-handler (acolyte tick :after) (dt)
  (unless (frozen-p)
    (run-cooldowns acolyte dt)))

;;; The storm: a spell circle (spells.lisp) whose sign draws itself in while the acolyte holds
;;; its fireball up, then burns while it holds its hand out, and dies down when it stops. It
;;; follows the caster's state as the gale sign does (wraith.lisp), so a flinch, the caster's
;;; death or a reset end it at one stroke.

(define-shader-entity firestorm (spell-circle)
  ((target :initarg :target :initform NIL :accessor storm-target :documentation "What it drifts after.")
   (burning :initform NIL :accessor burning :documentation "Seconds since it came down, or NIL before.")
   (fading :initform NIL :accessor fading :documentation "Seconds since it began to die down, or NIL.")
   (pulse-timer :initform 0.0 :accessor pulse-timer :documentation "Seconds to its next burn.")
   (cinder-timer :initform 0.0 :accessor cinder-timer :documentation "Seconds to the next cinder falling.")
   (ember-timer :initform 0.0 :accessor ember-timer)
   (room-timer :initform 0.0 :accessor room-timer :documentation "Seconds to the next look at the ceiling.")
   (ceiling :initform NIL :accessor storm-ceiling :documentation "The lowest ceiling over it, or NIL.")
   (scratch :initform (vec 0 0 0) :reader storm-scratch :documentation "A point for the sparks, reused.")))

(defmethod leave :after ((storm firestorm) container)
  (let ((caster (caster storm)))
    (when (and caster (eq storm (acolyte-storm caster)))
      (setf (acolyte-storm caster) NIL))))

(defun light-firestorm (storm)
  "Raise STORM's aurora, lamp and loop, the first time it ticks in the scene (or after a load)."
  (let ((c (centre storm)))
    (setf (circle-sound storm) (start-loop (spell-sound (spell storm) (if (burning storm) :storm :circle)) c)
          ;; Its centre is the storm's own, so the aurora drifts with it.
          (circle-aurora storm) (make-instance 'aurora :centre c :radius (circle-radius (spell storm))
                                                       :colors *firestorm-aurora-colors*
                                                       :spin *firestorm-aurora-spin* :twist *firestorm-aurora-twist*)
          (circle-lamp storm) (add-lamp (vec (vx c) (+ (vy c) 0.8) (vz c)) *firestorm-light-color*
                                        *firestorm-light-radius* :flicker 0.35))
    (enter (circle-aurora storm) (container storm))))

(defun ignite-firestorm (storm)
  "The storm comes down: it burns from now on."
  (let ((c (centre storm)))
    (setf (burning storm) 0.0
          (pulse-timer storm) 0.0
          (cinder-timer storm) 0.0
          (circle-sound storm) (stop-loop (circle-sound storm)))
    (setf (circle-sound storm) (start-loop (spell-sound (spell storm) :storm) c))
    (play-sound (spell-sound (spell storm) :ignite) c)
    (let ((at (storm-scratch storm)))
      (setf (vx at) (vx c) (vy at) (+ (vy c) 0.2) (vz at) (vz c))
      (spray-sparks at NIL 24 :kind :ember :ramp :fire :speed '(1.0 3.0)))))

(defun storm-strength (storm)
  "How bright STORM is: rising through the draw-in, a flash as it comes down, dying down at the end."
  (let ((burning (burning storm))
        (fading (fading storm)))
    (cond (fading (max 0.0 (- 1.0 (/ fading *firestorm-fade*))))
          (burning (+ 1.0 (* *firestorm-flash* (max 0.0 (- 1.0 (/ burning *firestorm-flash-time*))))))
          (T (expt (min 1.0 (/ (age storm) *firestorm-telegraph*)) 1.5)))))

(defun storm-pulse (storm)
  "Burn everything with feet in STORM but its caster."
  (let* ((caster (caster storm))
         (damage (effect-magnitude (first (spell-effects (spell storm))))))
    (destructuring-bind (rate time) *firestorm-afterburn*
      (loop for c across *creatures*
            when (and (not (dead c)) (not (eq c caster)) (in-circle-p storm (location c) (body-radius c)))
              do (burn c (resisted c :fire (roll damage)) :by caster)
                 (unless (dead c)
                   (afflict c :damage rate time :element :fire :caster caster)))
      (let ((player *player*))
        (when (and player (< 0 (health player)) (in-circle-p storm (feet player) *player-radius*))
          (play-sound :player-burn)
          (hurt-player player (roll damage) (centre storm) :shove NIL :unblockable T :by caster)
          (when (< 0 (health player))
            (afflict player :damage rate time :element :fire :caster caster)))))))

(defun drift-storm (storm dt)
  "Move STORM's centre toward its target's feet, along the floor: not up or down a ledge, onto
deep water or into a solid."
  (let ((target (storm-target storm))
        (c (centre storm)))
    (when (and target *nav-grid* (target-live-p target))
      (let* ((feet (body-feet target))
             (dx (- (vx feet) (vx c)))
             (dz (- (vz feet) (vz c)))
             (d (sqrt (+ (* dx dx) (* dz dz)))))
        (when (< 0.05 d)
          (let* ((step (min d (* *firestorm-drift* dt)))
                 (x (+ (vx c) (* step (/ dx d))))
                 (z (+ (vz c) (* step (/ dz d))))
                 (floor (nav-floor-at x (+ (vy c) 0.5) z)))
            (when (and floor
                       (< (abs (- floor (vy c))) 0.5)
                       (not (swim-liquid-at x (- floor 0.1) z))
                       (not (solid-at x (+ floor 0.3) z)))
              (setf (vx c) (float x 0f0) (vy c) (float floor 0f0) (vz c) (float z 0f0)))))))))

(defun update-storm-room (storm)
  (let ((c (centre storm)))
    (setf (storm-ceiling storm) (and *nav-grid* (nth-value 1 (nav-room-around (vx c) (+ (vy c) 0.3) (vz c) 1.0 0.5))))))

(defun rain-cinders (storm dt)
  "Now and then a cinder falls on a random point of STORM."
  (when (<= (decf (cinder-timer storm) dt) 0)
    (incf (cinder-timer storm) (/ (+ 0.5 (random 1.0)) *firestorm-cinders*))
    (let* ((c (centre storm))
           (r (* (circle-radius (spell storm)) (sqrt (random 1.0))))
           (a (random (float (* 2 pi) 0f0)))
           (x (+ (vx c) (* r (cos a))))
           (z (+ (vz c) (* r (sin a))))
           (floor (vy c))
           (top (+ floor *firestorm-cinder-height*)))
      (when (storm-ceiling storm)
        (setf top (min top (- (storm-ceiling storm) 0.3))))
      (unless (or (< top (+ floor 1.0)) (solid-at x (+ floor 0.5) z) (solid-at x top z))
        (enter (make-instance 'falling-cinder :animation (find-fx-animation 'cinder-flight)
                                              :location (vec x top z) :floor-y floor)
               (container storm))))))

(defun storm-embers (storm dt)
  "Embers rising from round STORM's rim."
  (when (<= (decf (ember-timer storm) dt) 0)
    (incf (ember-timer storm) (/ (+ 0.5 (random 1.0)) *firestorm-embers*))
    (let* ((c (centre storm))
           (r (* (circle-radius (spell storm)) (+ 0.7 (random 0.3))))
           (a (random (float (* 2 pi) 0f0)))
           (at (storm-scratch storm)))
      (setf (vx at) (+ (vx c) (* r (cos a))) (vy at) (+ (vy c) 0.1) (vz at) (+ (vz c) (* r (sin a))))
      (spray-sparks at NIL 1 :kind :ember :ramp :fire))))

(defun burn-storm (storm dt)
  "Run DT seconds of STORM burning."
  (incf (burning storm) dt)
  (drift-storm storm dt)
  (when (<= (decf (pulse-timer storm) dt) 0)
    (incf (pulse-timer storm) *firestorm-pulse*)
    (storm-pulse storm))
  (when (<= (decf (room-timer storm) dt) 0)
    (setf (room-timer storm) 1.0)
    (update-storm-room storm))
  (rain-cinders storm dt)
  (storm-embers storm dt))

(defun show-firestorm (storm)
  "STORM's sign, aurora, lamp and loop where its centre is now, as bright as it is."
  (let* ((c (centre storm))
         (loc (location storm))
         (atlas (animation-atlas (sprite-animation storm)))
         (count (getf atlas :frames))
         (k (storm-strength storm))
         (aurora (circle-aurora storm))
         (lamp (circle-lamp storm)))
    (setf (vx loc) (vx c) (vy loc) (+ (vy c) 0.01) (vz loc) (vz c))
    (strip-uv (frame-uv storm) atlas (sign-frame (age storm) *firestorm-telegraph* count) count)
    (when aurora
      (raise-aurora aurora (age storm) *firestorm-telegraph* (min 1.0 k))
      (let ((ceiling (storm-ceiling storm)))
        (when ceiling
          (setf (aurora-height aurora) (max 0.3 (min (aurora-height aurora) (- ceiling (vy c) 0.2))))))
      (when (fading storm)
        (setf (aurora-height aurora) (* (aurora-height aurora) k))))
    (when lamp
      (let ((at (location lamp))
            (color (color lamp)))
        (setf (vx at) (vx c) (vy at) (+ (vy c) 0.8) (vz at) (vz c)
              (vx color) (* k (vx *firestorm-light-color*))
              (vy color) (* k (vy *firestorm-light-color*))
              (vz color) (* k (vz *firestorm-light-color*)))))
    (move-loop (circle-sound storm) c)))

;; Its own tick, not SPELL-CIRCLE's: what it does follows its caster, and it lies flat.
(define-handler (firestorm tick) (dt)
  (let ((caster (caster firestorm)))
    (when (and (null (circle-lamp firestorm)) (null (fading firestorm)) (container firestorm))
      (light-firestorm firestorm))
    ;; A load restores the storm and its caster apart: link them again.
    (when (and caster (null (acolyte-storm caster)) (null (fading firestorm)) (container firestorm))
      (setf (acolyte-storm caster) firestorm))
    (unless (frozen-p)
      (incf (age firestorm) dt)
      (cond ((fading firestorm)
             (when (< *firestorm-fade* (incf (fading firestorm) dt))
               (despawn firestorm)))
            ((burning firestorm)
             (if (storming-p caster)
                 (burn-storm firestorm dt)
                 (setf (fading firestorm) 0.0
                       (circle-sound firestorm) (stop-loop (circle-sound firestorm)))))
            ((not (casting-firestorm-p caster))
             (despawn firestorm))))
    (when (container firestorm)
      (show-firestorm firestorm))))

;;; The cinders falling on it: the cinder's own sprite, straight down, bursting on the floor.
;;; Only a look: the storm's burns do the harm.

(define-shader-entity falling-cinder (fx-sprite)
  ((floor-y :initarg :floor-y :initform 0.0 :reader floor-y)))

(defvar *cinder-sound-turn* NIL "Every other falling cinder sounds as it strikes.")

(define-handler (falling-cinder tick :after) (dt)
  (unless (frozen-p)
    (let ((loc (location falling-cinder)))
      (decf (vy loc) (* *firestorm-cinder-speed* dt))
      (when (<= (vy loc) (+ (floor-y falling-cinder) 0.2))
        (setf (vy loc) (+ (floor-y falling-cinder) 0.2))
        (spawn-fx 'bolt-burst loc (container falling-cinder))
        (spray-sparks loc NIL *firestorm-cinder-sparks* :ramp :lava)
        (when (setf *cinder-sound-turn* (not *cinder-sound-turn*))
          (play-sound :cinder-impact loc 0.7))
        (despawn falling-cinder)))))

(defun preload-firestorm (scene)
  "Load what an acolyte's firestorm spawns mid-game: the storm and its falling cinders."
  (preload (make-instance 'firestorm :spell (find-spell 'firestorm) :centre (vec 0 0 0)
                                     :animation (find-fx-animation 'firestorm-sign))
           scene)
  (preload (make-instance 'falling-cinder :animation (find-fx-animation 'cinder-flight)) scene))
