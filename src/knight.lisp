(in-package #:hexmaw)

;;; The knight: slow, in heavy plate, behind a tower shield from its feet to its helm.
;;; The shield turns spells away from the front and front-quarter views (and reflects
;;; them back), so the player gets behind it, where it turns only slowly, or closes in
;;; with the sword, which the shield doesn't stop.
;;;
;;; From level 2 of a run on (LEVEL-ABILITY-P :SHIELD-CHARGE) it also charges: its answer to a
;;; player who turtles behind a raised shield or stands off. With its target 3.5 to 10 m off, in
;;; sight and a straight run away on the nav grid, it crouches behind its shield (the tell, still
;;; turning to its target), then runs along the way it faced, hardly turning, to a few metres past
;;; where its target stood. Its shield stays up in front throughout. What it meets:
;;; - its target: a heavy blow that throws them down the line and knocks a raised shield aside;
;;; - another creature: bowled aside, once a charge, and the run goes on;
;;; - a wall: it crashes, and reels with its guard down (REEL), the punish window;
;;; - lava, water or a drop it can't step down: it stops short.
;;; A sidestep makes it miss. The spear set against it from the front stops it (spear.lisp), the
;;; maul's earthshake flinches it out of the run, and a flinch from behind ends it like any attack.

(defparameter *knight-height* 1.95 "Knight height in metres, helm to sabatons, about the shield's height.")

;; Sliced at 125 px tall, so its art pixels are the imp's size (96 px for 1.5 m).
(define-asset (hexmaw knight-turnaround) image
    #p"sprites/knight/turnaround.png"
  :min-filter :nearest :mag-filter :nearest)

;; The block: impact (the shield's face lit by the splash), then the brace, crouched
;; behind the raised shield; two frames for each of the views the shield covers (front
;; and front-quarter), over *BLOCK-TIME*. Its cells are 112 px tall, at the turnaround's
;; scale. The charge's tell holds the brace.
(define-fx-animation knight-block "sprites/knight/block" :size (* *knight-height* 112/125))
;; A slow, heavy stride, four frames per view, the shield held up in front. Its cells are
;; 132 px tall for the rise on the passing frames, the standing knight 125 px. The frame
;; follows the distance walked (STRIDE), so :FPS is unused. The charge runs on it too, at a
;; longer stride.
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

;;; The shield charge.

(defparameter *charge-min* 3.5 "Least distance, in metres across, the knight charges from: beyond its lunge.")
(defparameter *charge-max* 10.0 "Furthest it charges from.")
(defparameter *charge-rise* 1.0 "Most metres its target's feet may be above or below its own.")
(defparameter *charge-chance* 30
  "Percent chance, each time its hunt asks (every *CHASE-REPLAN*), that it charges a target whose
shield isn't raised at it; one whose is, it always charges.")
(defparameter *charge-cooldown* 10.0 "Seconds from one charge setting off to the next, before the depth's :COOLDOWN.")
(defparameter *charge-first* 3.0 "Seconds before a knight's first charge, so it doesn't charge as it notices the player.")
(defparameter *charge-retry* 3.0 "Seconds before it may try again after a charge broken off in its tell.")
(defparameter *charge-windup* 0.8 "Seconds of the tell, crouched behind its shield.")
(defparameter *charge-speed* 7.5 "Metres per second it runs: a little faster than the player runs.")
(defparameter *charge-turn* 0.3 "Radians per second it turns toward its target once it runs.")
(defparameter *charge-overshoot* 3.0 "Metres it runs past where its target stood as it set off.")
(defparameter *charge-max-run* 14.0 "Most metres it runs.")
(defparameter *charge-reach* 0.15 "Metres between the bodies at which the run strikes its target.")
(defparameter *charge-hit-arc* 0.7 "Radians either side of the way it runs that its target is struck within.")
(defparameter *charge-damage* '(14 20))
(defparameter *charge-shove* 11.0 "Speed in m/s it throws its target, down the line of the run.")
(defparameter *charge-lift* 3.0 "Speed in m/s it throws the player up.")
(defparameter *charge-guard-break* 1.2 "Seconds a raised shield it strikes stays knocked aside (BREAK-GUARD).")
(defparameter *charge-recover* 0.7 "Seconds it stands after a run that crashed into nothing.")
(defparameter *charge-bowl-speed* 8.0 "Speed in m/s it bowls another creature in its way aside, before that one's KNOCKBACK-SCALE.")
(defparameter *charge-bowl-damage* '(3 5))
(defparameter *charge-crash-reel* 1.5 "Seconds it reels, guard down, after running into a wall.")
(defparameter *charge-boss-crash-reel* 0.6)
(defparameter *charge-spear-reel* 1.0 "Seconds it reels after the spear set against it stopped its charge.")
(defparameter *charge-boss-spear-reel* 0.5)
(defparameter *charge-stall-time* 0.2 "Seconds it may be held up (a body that won't move) before the run ends.")
(defparameter *charge-stride* 0.75 "Metres per walk frame while it runs (the walk's STRIDE is 0.3).")
(defparameter *charge-crouch* 1.5 "How squashed its tell is drawn seen from the side or back, as a flinch's squash.")
(defparameter *charge-paw-interval* 0.25 "Seconds between the scrapes of grit its feet kick up in the tell.")
(defparameter *charge-camera-shake* 0.5 "Strength of the camera kick of its crash, full within 2 m (KICK-CAMERA-FROM).")
(defparameter *charge-shake-reach* 10.0)
(defparameter *charge-crash-hit-stop* 0.05)
(defparameter *charge-debug* NIL "When true, log every charge, refusal and stop.")

(defun charge-log (knight format &rest args)
  (when *charge-debug*
    (v:info :hexmaw "~:(~a~) at ~,1f ~,1f: ~?" (type-of knight) (vx (location knight)) (vz (location knight)) format args)))

(defun knight-abilities ()
  ;; The mace first: its usual blow, the one an attack in reach is.
  (list (make-instance 'ability :name :mace :animation 'knight-attack
                                :frame-times '(0.4 0.12 0.25 0.4) :hit-frame 2 :pause 0.6)
        ;; No animation: SHOW-OWN-POSE draws the tell and the run. The frames are the tell and
        ;; the run, which ends on its own (CHARGE-STEP), so WINDING-UP-P holds through the tell.
        (make-instance 'ability :name :shield-charge :frame-times (list *charge-windup* 1000.0) :hit-frame 1
                                :pause *charge-recover* :cooldown *charge-cooldown*)))

(define-shader-entity knight (ability-user creature)
  ((texture :initform (// 'hexmaw 'knight-turnaround))
   (atlas :initform (read-atlas "sprites/knight/turnaround.lisp"))
   (sprite-height :initform *knight-height*)
   (walk-animation :initform 'knight-walk)
   (attack-animation :initform 'knight-attack)
   (hurt-animation :initform 'knight-hurt)
   (death-animation :initform 'knight-death)
   (abilities :initform (knight-abilities))
   (cooldowns :initform (list :shield-charge *charge-first*))
   (stride :initform 0.3)
   (body-radius :initform 0.45)
   (shield-views :initform 1)
   (block-animation :initform 'knight-block)
   (turn-speed :initform 3.0)
   (knockback-scale :initform 0.35)
   (attack-damage :initform '(12 18))
   (attack-reach :initform 0.8)
   (attack-arc :initform 0.7)
   ;; A heavy blow, stepping in behind the shield as the mace comes over.
   (attack-frame-times :initform '(0.4 0.12 0.25 0.4))
   (attack-pause :initform 0.6)
   (lunge-speed :initform 3.0)
   ;; The mace beats a raised shield aside.
   (guard-break :initform 0.8)
   (walk-speed :initform 0.9)
   (chase-speed :initform 2.2)
   (wander-radius :initform 2.0)
   ;; Flesh from inside the plate, drawn bigger for its size. No single blow overkills
   ;; 60 health by the usual fraction, so it tears apart more easily.
   (gibs :initform '((:flesh 0 0 1 1 2 3 4 5 5 6 6 7 7)))
   (gib-scale :initform 1.3)
   (gib-overkill :initform 0.15)
   ;; Plate and a steady stance: most blows don't stagger it.
   (pain-chance :initform 8)
   (max-health :initform 60)
   (charge :initform NIL :accessor charge
           :documentation "Where its shield charge is: :WINDUP (the tell), :RUNNING, or NIL.")
   (charge-yaw :initform 0.0 :accessor charge-yaw :documentation "The way it runs.")
   (charge-left :initform 0.0 :accessor charge-left :documentation "Metres it has still to run.")
   (charge-stall :initform 0.0 :accessor charge-stall :documentation "Seconds it has been held up.")
   (charge-bowled :initform () :accessor charge-bowled :documentation "The creatures it has bowled aside this charge.")
   (charge-paw :initform 0.0 :accessor charge-paw :documentation "Seconds until its feet scrape again in the tell.")))

;; The charge's tell bellows (its alert), the mace's wind-up is the mace's; the charge's blow and
;; its crash are a shield bash's and a guard knocked aside.
(define-creature-sounds knight
  :alert :knight-alert :pain :knight-pain :death :knight-death :step :step-armour
  :ram :bash-hit :crash :maul-guard-break)

(defmethod creature-sound ((knight knight) (event (eql :windup)))
  (if (eq :shield-charge (ability-name (current-ability knight))) :knight-alert :knight-mace))

;; An ABILITY-USER is a caster by default; the knight closes in for every attack.
(defmethod ranged-p ((knight knight)) NIL)

(defun shield-charging-p (creature)
  "True while CREATURE is a knight running its shield charge."
  (and (typep creature 'knight) (eq (charge creature) :running) (not (dead creature))))

(defmethod charging-p ((knight knight))
  (and (shield-charging-p knight) (hunting-p knight)))

(defgeneric charge-damage (knight)
  (:documentation "The damage KNIGHT's charge does its target: a boss's more (boss.lisp).")
  (:method ((knight knight)) (roll *charge-damage*)))

(defgeneric charge-reel-time (knight cause)
  (:documentation "Seconds KNIGHT reels after its charge was stopped by CAUSE: :CRASH into a wall, or
the :SPEAR set against it. A boss's are shorter (boss.lisp).")
  (:method ((knight knight) cause)
    (ecase cause (:crash *charge-crash-reel*) (:spear *charge-spear-reel*))))

(defun charge-ready-p (knight)
  "True if KNIGHT may start a shield charge at what it hunts now."
  (let ((target (hunt-target knight)))
    (and target *nav-grid*
         (level-ability-p :shield-charge)
         (ready-p knight :shield-charge)
         (not (whirl knight))
         (target-live-p target)
         (not (target-swimming-p target))
         (<= *charge-min* (target-distance knight target) *charge-max*)
         (< (abs (- (vy (body-feet target)) (vy (location knight)))) *charge-rise*)
         (or (target-guarding-p target (location knight))
             (< (random 100 *roll-random*) *charge-chance*))
         (clear-path-p (location knight) (body-feet target) (cast-height knight))
         ;; A run that reaches its target: the line to where the bodies meet, since its own body
         ;; may not fit where the target stands (against a wall).
         (let* ((*nav-hazards* :avoid)
                (*nav-bodies* NIL)
                (from (ground-point knight))
                (feet (body-feet target))
                (dx (- (vx feet) (vx from)))
                (dz (- (vz feet) (vz from)))
                (k (/ (+ (body-radius knight) (body-radius target)) (max 1f-3 (sqrt (+ (* dx dx) (* dz dz))))))
                (to (vec (- (vx feet) (* k dx)) (vy feet) (- (vz feet) (* k dz)))))
           (or (nav-line-clear-p from to (body-radius knight) (sprite-height knight) (step-height knight))
               (progn (charge-log knight "no straight run to the target") NIL))))))

(defmethod special-attack ((knight knight))
  (when (charge-ready-p knight)
    (setf (charge knight) :windup
          (charge-stall knight) 0.0
          (charge-paw knight) 0.0
          (charge-bowled knight) ()
          ;; Broken off in the tell, it may try again a little later.
          (getf (cooldowns knight) :shield-charge) *charge-retry*)
    (charge-log knight "crouches to charge, ~,1f m off" (target-distance knight))
    (start-ability knight :shield-charge)
    T))

(defmethod attack-step ((knight knight) dt)
  (if (eq :shield-charge (ability-name (current-ability knight)))
      (charge-step knight dt)
      (call-next-method)))

(defun end-charge (knight pause)
  "End KNIGHT's charge and stand PAUSE seconds (before the depth's :PAUSE). On ice the run's speed
carries on as its momentum, so it skids."
  (when (and (eq (charge knight) :running) (footing knight))
    (let ((kb (momentum knight))
          (speed (float *charge-speed* 0f0)))
      (setf (vx kb) (* speed (sin (charge-yaw knight)))
            (vz kb) (- (* speed (cos (charge-yaw knight)))))))
  (setf (charge knight) NIL
        (charge-bowled knight) ())
  (stop-walking knight (* pause (depth-scale :pause))))

(defun reel-from-charge (knight cause)
  "KNIGHT's charge was stopped hard by CAUSE (CHARGE-REEL-TIME): it reels, its guard down."
  (let ((time (charge-reel-time knight cause)))
    (end-charge knight 0.0)
    (setf (reel knight) (float time 0f0)
          (brace knight) 0.0)
    (stop-walking knight time)))

(defun launch-charge (knight)
  "The tell is over: KNIGHT runs the way it faces, to *CHARGE-OVERSHOOT* past where its target stands."
  (let* ((target (hunt-target knight))
         (yaw (facing knight))
         (along (if target
                    (let* ((loc (location knight))
                           (feet (body-feet target)))
                      (+ (* (- (vx feet) (vx loc)) (sin yaw)) (* (- (vz feet) (vz loc)) (- (cos yaw)))))
                    0.0)))
    (setf (charge knight) :running
          (attack-pending knight) NIL
          (charge-yaw knight) yaw
          (charge-left knight) (float (min *charge-max-run* (+ (max 0.0 along) *charge-overshoot*)) 0f0)
          (getf (cooldowns knight) :shield-charge) (* *charge-cooldown* (depth-scale :cooldown)))
    (charge-log knight "charges, ~,1f m to run" (charge-left knight))))

(defun steer-charge (knight target dt)
  "Turn KNIGHT's run toward TARGET by at most *CHARGE-TURN* radians a second."
  (let* ((loc (location knight))
         (feet (body-feet target))
         (to (atan (- (vx feet) (vx loc)) (- (vz loc) (vz feet))))
         (now (charge-yaw knight))
         (diff (- (mod (+ (- to now) pi) (* 2 pi)) pi))
         (most (* *charge-turn* dt))
         (yaw (float (- (mod (+ now (max (- most) (min most diff)) pi) (* 2 pi)) pi) 0f0)))
    (setf (charge-yaw knight) yaw
          (facing knight) yaw)))

(defun charge-edge-ahead-p (knight fx fz)
  "True if just ahead of KNIGHT, running along FX FZ, is a liquid or a drop deeper than it steps."
  (let* ((loc (location knight))
         (out (+ (body-radius knight) 0.3))
         (x (+ (vx loc) (* out fx)))
         (z (+ (vz loc) (* out fz)))
         (floor (nav-floor-at x (+ (vy loc) (step-height knight)) z)))
    (if floor
        (or (< (+ floor (step-height knight)) (vy loc))
            (liquid-at x (+ floor 0.05) z)
            (liquid-at x (- floor 0.1) z))
        ;; No floor in a wall is the wall, which the run crashes into; no floor in the open, a hole.
        (not (solid-at (float x 0f0) (float (+ (vy loc) 1.0) 0f0) (float z 0f0))))))

(defun bowl-aside (knight body fx fz)
  "KNIGHT's charge meets BODY, not what it hunts: hurt a little and shoved off the line, mostly sideways."
  (push body (charge-bowled knight))
  (let* ((loc (location knight))
         (at (body-feet body))
         ;; Which side of the line BODY stands on: its right is (-FZ, FX).
         (side (if (< 0 (- (* (- (vz at) (vz loc)) fx) (* (- (vx at) (vx loc)) fz))) 1.0 -1.0))
         ;; Struck from a point ahead-and-across, so it is thrown to its side and a little on.
         (from (vec (- (vx at) (* 0.45 fx) (* side -1.0 fz)) (vy at) (- (vz at) (* 0.45 fz) (* side fx)))))
    (charge-log knight "bowls ~(~a~) aside" (type-of body))
    (creature-noise knight :ram 0.7)
    (strike-target body (roll *charge-bowl-damage*) from :shove *charge-bowl-speed* :lift 1.0 :by knight)))

(defun charge-strike (knight target fx fz)
  "KNIGHT's charge meets its TARGET: thrown down the line of the run."
  (let* ((feet (body-feet target))
         (from (vec (- (vx feet) fx) (vy feet) (- (vz feet) fz))))
    (creature-noise knight :ram)
    (shield-sparks knight 10)
    (let* ((damage (charge-damage knight))
           (blocked (strike-target target damage from :shove *charge-shove* :lift *charge-lift*
                                                      :guard-break *charge-guard-break* :by knight)))
      (charge-log knight "strikes ~(~a~) for ~d~:[~; on its shield~]" (type-of target) damage blocked))
    (end-charge knight *charge-recover*)))

(defun crash-charge (knight fx fz)
  "KNIGHT ran its shield into a wall: sparks and grit off it, the floor shakes, and it reels."
  (let* ((loc (location knight))
         (r (body-radius knight))
         (y (+ (vy loc) (* *shield-spark-height* (sprite-height knight)))))
    (charge-log knight "crashes into a wall")
    (multiple-value-bind (s hx hy hz nx ny nz) (wall-strike-point (vx loc) y (vz loc) fx 0.0 fz (+ r 0.6))
      (if s
          (wall-sparks hx hy hz nx ny nz fx 0.0 fz (solid-strike s) :sparks 18 :grit 10)
          (shield-sparks knight 14)))
    (creature-noise knight :crash)
    (kick-dust (vec (+ (vx loc) (* r fx)) (vy loc) (+ (vz loc) (* r fz))) 0.3 3 (container knight))
    (kick-camera-from loc *charge-camera-shake* *charge-shake-reach*)
    (hit-stop *charge-crash-hit-stop*)
    (reel-from-charge knight :crash)))

(defun charge-contact-p (knight target body-ahead fx fz step)
  "True if KNIGHT's run, STEP metres on along FX FZ, meets its TARGET: within reach in front, or the
body in its way."
  (or (eq body-ahead target)
      (and (target-within-p knight (+ *charge-reach* step) target)
           (let* ((loc (location knight))
                  (feet (body-feet target))
                  (dx (- (vx feet) (vx loc)))
                  (dz (- (vz feet) (vz loc)))
                  (d (sqrt (+ (* dx dx) (* dz dz)))))
             (or (< d 1f-3)
                 (< (acos (max -1.0 (min 1.0 (/ (+ (* dx fx) (* dz fz)) d)))) *charge-hit-arc*))))))

(defun run-charge (knight dt)
  (let* ((target (hunt-target knight))
         (target (and target (target-live-p target) target)))
    (when target
      (steer-charge knight target dt))
    (let* ((yaw (charge-yaw knight))
           (fx (sin yaw))
           (fz (- (cos yaw)))
           (step (* *charge-speed* dt))
           (loc (location knight))
           (r (float (body-radius knight) 0f0))
           (h (float (sprite-height knight) 0f0))
           (body (nth-value 1 (body-overlapping (+ (vx loc) (* (+ step 0.1) fx)) (+ (vy loc) 0.05)
                                                (+ (vz loc) (* (+ step 0.1) fz)) r (- h 0.05) knight))))
      (cond ((and target (charge-contact-p knight target body fx fz step))
             (charge-strike knight target fx fz))
            ((charge-edge-ahead-p knight fx fz)
             (charge-log knight "stops short of an edge")
             (end-charge knight *charge-recover*))
            (T
             (when (and body (not (member body (charge-bowled knight))) (target-live-p body))
               (bowl-aside knight body fx fz))
             (let ((x0 (vx loc))
                   (z0 (vz loc)))
               (move-creature knight (* step fx) (* step fz) (step-height knight))
               (let ((moved (sqrt (+ (expt (- (vx loc) x0) 2) (expt (- (vz loc) z0) 2)))))
                 (incf (walk-distance knight) (* moved (/ (stride knight) *charge-stride*)))
                 (decf (charge-left knight) moved)
                 (cond ((and (< moved (* 0.5 step))
                             (solid-overlapping (+ (vx loc) (* (+ step 0.05) fx)) (+ (vy loc) (step-height knight))
                                                (+ (vz loc) (* (+ step 0.05) fz)) r (- h (step-height knight))))
                        (crash-charge knight fx fz))
                       ((< moved (* step 1/3))
                        (when (< *charge-stall-time* (incf (charge-stall knight) dt))
                          (charge-log knight "held up")
                          (end-charge knight *charge-recover*)))
                       (T (setf (charge-stall knight) 0.0)))
                 (when (and (eq (charge knight) :running) (<= (charge-left knight) 0))
                   (charge-log knight "runs out")
                   (end-charge knight *charge-recover*)))))))))

(defun charge-step (knight dt)
  "Run DT seconds of KNIGHT's shield charge: the tell, then the run."
  (let ((time (incf (attack-time knight) dt)))
    (case (charge knight)
      (:windup
       (face-attack-target knight dt)
       (when (<= (decf (charge-paw knight) dt) 0)
         ;; It scrapes its feet, kicking up grit behind it.
         (setf (charge-paw knight) *charge-paw-interval*)
         (let ((loc (location knight))
               (yaw (facing knight))
               (back (* 0.4 (body-radius knight))))
           (kick-grit (- (vx loc) (* back (sin yaw))) (vy loc) (+ (vz loc) (* back (cos yaw))) 4)
           (creature-noise knight :step 0.6)))
       (when (<= *charge-windup* time)
         (launch-charge knight)))
      (:running (run-charge knight dt))
      ;; An attack with the charge's ability and no charge (a save from mid-switch): over.
      (T (end-charge knight 0.0)))))

;; The spear's counter on the run from behind or the side (spear.lisp): the charge is over.
(defmethod impale ((knight knight))
  (when (eq (charge knight) :running)
    (charge-log knight "impaled")
    (end-charge knight 0.0)))

;; A vortex took it (vortex.lisp).
(defmethod break-flight :after ((knight knight))
  (setf (charge knight) NIL
        (charge-bowled knight) ()))

(defmethod show-own-pose ((knight knight) squash)
  (case (and (not (dead knight)) (eq (brain knight) :attacking)
             (eq :shield-charge (ability-name (current-ability knight)))
             (charge knight))
    (:windup
     ;; Crouched behind its shield: the block's brace where it has the view, else the walk's
     ;; first frame pressed down.
     (if (<= (view-index knight) (shield-views knight))
         (show-view-frame knight (block-animation knight) 1 (max squash 0.5) (1+ (shield-views knight)))
         (show-view-frame knight (walk-animation knight) 0 (max squash *charge-crouch*)))
     T)
    (:running
     (show-view-frame knight (walk-animation knight) (floor (walk-distance knight) (stride-length knight)) squash)
     T)
    (T (call-next-method))))

(define-handler (knight tick :after) (dt)
  (unless (frozen-p)
    (run-cooldowns knight dt)
    ;; Back to the mace once an attack is over, so the next blow in reach is one; a charge
    ;; broken off (a flinch, a reel, its death) is forgotten.
    (unless (eq (brain knight) :attacking)
      (setf (current-ability knight) (first (abilities knight)))
      (when (charge knight)
        (setf (charge knight) NIL
              (charge-bowled knight) ())))))
