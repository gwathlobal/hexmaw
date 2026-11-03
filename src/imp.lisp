(in-package #:hexmaw)

;;; The imp: small, quick and craven, the monster met most. It hunts in packs and darts in
;;; and out rather than standing to trade blows:
;;;
;;; - Pounce. From 3 to 7 m it crouches (*POUNCE-WINDUP*, the warning) and leaps at the
;;;   player, the ogre's leap (ogre.lisp) made short, low and quick. Reaching the player in
;;;   the air it claws them; the raised shield takes the claw and throws it down, and so
;;;   does any blow that lands while it flies (KNOCK-DOWN): it lies DOWNED a moment. A timed
;;;   bash in the crouch interrupts it like any wind-up.
;;; - Hit and run. After every claw it springs back out of reach (SPRING-FROM-PLAYER) and
;;;   gives up its spot round the player (BAN-SLOT), so it comes in again from elsewhere.
;;; - Morale. Its COURAGE is its health with a bonus for every packmate near. Once in a life,
;;;   when it falls below *IMP-BREAK-COURAGE*, it shrieks (every creature within
;;;   *SHRIEK-RANGE* hears and hunts) and runs for *IMP-FLEE-TIME*, then comes back.
;;; - Thief. A claw that lands may snatch a potion from the player (TAKE-ITEM), and a
;;;   wandering imp takes pickups off the floor. Carrying, it holds the loot over its head
;;;   and keeps away, fighting only when cornered; killed, it drops it (CREATURE-DIED).
;;; - Packs. Each imp a block spawns may bring one or two more (SPREAD-PACKS).
;;;
;;; A boss (boss.lisp) of its kind keeps only the pounce: SKITTISH-P is NIL for it.

(defparameter *imp-height* 1.5
  "Imp height in metres, horns to feet. The player's eye is at 1.6.")

(defparameter *pounce-min* 3.0 "Least distance, in metres across, an imp pounces from.")
(defparameter *pounce-max* 7.0 "Furthest it pounces from.")
(defparameter *pounce-max-rise* 1.5 "Highest, in metres, it pounces up onto.")
(defparameter *pounce-max-drop* 3.0 "Lowest it pounces down to.")
(defparameter *pounce-rise* 0.7 "Metres its feet rise above the higher end of a pounce.")
(defparameter *pounce-min-rise* 0.3 "Lowest rise it still pounces with.")
(defparameter *pounce-gravity* 22.0 "Acceleration, in m/s², along its arc: a flat, quick leap.")
(defparameter *pounce-max-speed* 14.0 "Fastest, in m/s across, it flies.")
(defparameter *pounce-windup* 0.45 "Seconds it crouches before it pounces: the warning.")
(defparameter *pounce-recover* 0.4 "Seconds it stands after landing.")
(defparameter *pounce-cooldown* 5.0 "Seconds from one pounce to the next.")
(defparameter *pounce-reach* 0.2 "Metres between its body and the player's at which the pounce's claw lands.")
(defparameter *pounce-damage-scale* 1.2 "The pounce's damage against its claw's.")
(defparameter *pounce-rebound* 3.0 "Speed in m/s it bounces back off the player its pounce struck.")
(defparameter *pounce-blocked-rebound* 5.0 "Speed in m/s it bounces back off a raised shield.")
(defparameter *imp-downed-time* 1.0 "Seconds it lies knocked down out of a pounce.")

(defparameter *imp-spring-speed* 6.0
  "Speed in m/s it springs back after a claw: about 1.3 m, out of the sword's reach.")
(defparameter *imp-spring-angle* '(0.4 0.8)
  "Least and most radians off straight back it springs, to one side or the other: it comes in
again from elsewhere.")

(defparameter *imp-pack-courage* 0.3 "Courage each live packmate within *IMP-PACK-RADIUS* gives an imp.")
(defparameter *imp-pack-radius* 8.0 "Metres within which another imp counts as its pack.")
(defparameter *imp-break-courage* 0.5
  "Courage (its share of health, plus *IMP-PACK-COURAGE* a packmate) below which it breaks and runs.")
(defparameter *shriek-time* 0.7 "Seconds it stands shrieking before it runs.")
(defparameter *shriek-range* 15.0 "Metres within which creatures hear the shriek and hunt the player.")
(defparameter *shriek-rise* 3.0 "Metres above or below it that the shriek is heard: its storey.")
(defparameter *shriek-alert-time* 8.0 "Seconds the creatures that hear it hunt.")
(defparameter *imp-flee-time* 5.0 "Seconds a broken imp runs before it rallies.")
(defparameter *imp-flee-speed* 1.2 "Its running speed while it flees, against its CHASE-SPEED.")
(defparameter *flee-walk* 14.0 "Longest walk, in metres, a flight looks along for where to run to.")
(defparameter *flee-min-walk* 4.0 "Shortest walk a flight takes.")
(defparameter *flee-safe-distance* 10.0 "Metres from the player at which a fleeing imp stops running and watches.")
(defparameter *imp-cornered-time* 3.0 "Seconds an imp with nowhere to run fights before it tries again.")

(defparameter *imp-steal-chance* 35 "Percent chance a claw that lands snatches one of the player's items.")
(defparameter *thief-keep-away* 6.0 "Metres within which an imp carrying loot runs from the player.")
(defparameter *thief-flee-time* 3.0 "Seconds it runs each time.")
(defparameter *thief-sniff-range* 6.0 "Metres within which a wandering imp goes for a pickup on the floor.")
(defparameter *thief-reach* 0.6 "Metres across from a pickup at which it takes it.")
(defparameter *thief-witness-range* 15.0
  "Metres from the player, on their storey, within which a wandering imp goes for a pickup on the
floor: the player sees it happen, and the level's pickups don't drain away out of sight.")

(defparameter *imp-pack-chance* 0.6 "Chance an imp a block spawns brings a pack.")
(defparameter *imp-pack-three* 0.4 "Chance a pack is three imps rather than two.")
(defparameter *pack-spacing* 1.2 "Metres from the first imp that the rest of its pack stand.")

;; Sliced so the standing imp in its first frame is as tall as a turnaround cell.
(define-fx-animation imp-death "sprites/imp/death" :fps 10 :size *imp-height*)
;; Four frames per view, every view scaled to a turnaround cell's height. The frame
;; follows the distance walked (STRIDE), so :FPS is unused.
(define-fx-animation imp-walk "sprites/imp/walk" :loop T :size *imp-height*)
;; The claw swipe: wind-up, lunge, strike, recover, four frames per view. Its cells are
;; 110 px tall to fit the raised claw, with the standing imp 96 px like the walk's.
;; The frames run on the imp's ATTACK-FRAME-TIMES, so :FPS is unused. The pounce shows
;; the first three: the crouch, the lunge in the air, the strike on landing.
(define-fx-animation imp-attack "sprites/imp/attack" :size (* *imp-height* 110/96))
;; The flinch: jolt, then stagger, two frames per view over *STAGGER-TIME*. Its cells
;; are 80 px tall, the buckled jolt at the walk's scale (standing imp 96 px). Knocked
;; down, it holds the stagger.
(define-fx-animation imp-hurt "sprites/imp/hurt" :size (* *imp-height* 80/96))

(define-shader-entity imp (leaper creature)
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
   ;; Short: it springs away after the blow and comes in again from elsewhere.
   (attack-pause :initform 0.35)
   (chase-speed :initform 2.6)
   ;; Quick and small: it darts round a raised shield.
   (flanks :initform T)
   (pain-chance :initform 60)
   (max-health :initform 30)
   (downed :initform 0.0 :accessor downed :documentation "Seconds left lying knocked out of a pounce.")
   (knocked :initform NIL :accessor knocked
            :documentation "True while it falls out of a pounce, knocked: it lands DOWNED.")
   (pounce-struck :initform NIL :accessor pounce-struck
                  :documentation "True once this pounce's claw has landed, or can't any more.")
   (shriek :initform 0.0 :accessor shriek :documentation "Seconds left of its shriek, before it runs.")
   (shrieked :initform NIL :accessor shrieked :documentation "True once it has broken and run, this life.")
   (fleeing :initform 0.0 :accessor fleeing :documentation "Seconds it still runs from the player.")
   (cornered :initform 0.0 :accessor cornered
             :documentation "Seconds it fights on, having found nowhere to run.")
   (stolen :initform NIL :accessor stolen :documentation "The kind of pickup it carries off, or NIL.")
   (steal-target :initform NIL :accessor steal-target :documentation "The pickup it walks to take, or NIL.")
   (loot-sprite :initform NIL :accessor loot-sprite :documentation "What it shows over its head while it carries loot.")))

(defgeneric skittish-p (imp)
  (:documentation "True if IMP breaks, runs, springs back and steals: an imp, but not a boss of its kind.")
  (:method ((imp imp)) T))

;;; The pounce: the ogre's leap, its own size.

(defmethod leap-min-distance ((imp imp)) *pounce-min*)
(defmethod leap-max-distance ((imp imp)) *pounce-max*)
(defmethod leap-max-rise ((imp imp)) *pounce-max-rise*)
(defmethod leap-max-drop ((imp imp)) *pounce-max-drop*)
(defmethod leap-rise ((imp imp)) *pounce-rise*)
(defmethod leap-min-rise ((imp imp)) *pounce-min-rise*)
(defmethod leap-max-speed ((imp imp)) *pounce-max-speed*)
(defmethod leap-gravity ((imp imp)) *pounce-gravity*)
(defmethod leap-windup ((imp imp)) *pounce-windup*)
(defmethod leap-recover-time ((imp imp)) *pounce-recover*)
(defmethod leap-cooldown-time ((imp imp)) *pounce-cooldown*)

(defun pounce (imp)
  "Start a pounce at the player if IMP may: true if it did."
  (when (try-leap imp)
    (setf (pounce-struck imp) NIL
          (knocked imp) NIL)
    T))

(defun spring-from-player (imp speed &optional (turn 0.0))
  "Send IMP sliding away from the player at SPEED m/s, TURN radians off straight back, its own
leap: no KNOCKBACK-SCALE."
  (let* ((loc (location imp))
         (feet (feet *player*))
         (dx (- (vx loc) (vx feet)))
         (dz (- (vz loc) (vz feet)))
         (len (sqrt (+ (* dx dx) (* dz dz))))
         (m (momentum imp)))
    (when (< len 1f-3)
      ;; Right on top of them: back the way it faces.
      (setf dx (- (sin (facing imp))) dz (cos (facing imp)) len 1.0))
    (let ((c (cos turn)) (s (sin turn)))
      (setf (vx m) (float (* speed (/ (- (* c dx) (* s dz)) len)) 0f0)
            (vz m) (float (* speed (/ (+ (* s dx) (* c dz)) len)) 0f0)))))

(defun knock-down (imp)
  "IMP is struck out of its pounce: it drops from where it is and lands downed."
  (setf (airborne imp) NIL
        (falling imp) T
        (fall-speed imp) 0.0
        (knocked imp) T
        (pounce-struck imp) T))

(defun pounce-strike (imp)
  "IMP's pounce reaches the player: its claw, then it bounces off, thrown down by a raised shield."
  (setf (pounce-struck imp) T)
  (let ((blocked (hurt-player *player* (max 1 (round (* *pounce-damage-scale* (roll (attack-damage imp)))))
                              (location imp) :by imp)))
    (setf (airborne imp) NIL
          (falling imp) T
          (fall-speed imp) 0.0)
    (spring-from-player imp (if blocked *pounce-blocked-rebound* *pounce-rebound*))
    (when (skittish-p imp)
      (if blocked
          (setf (knocked imp) T)
          (try-steal imp)))))

(defmethod leap-landed ((imp imp))
  (cond ((knocked imp)
         (setf (knocked imp) NIL
               (downed imp) *imp-downed-time*)
         (stop-walking imp *imp-downed-time*))
        (T
         (setf (recover imp) (leap-recover-time imp))
         (stop-walking imp (leap-recover-time imp)))))

;;; Morale.

(defun packmates (imp)
  "How many other live imps that run in packs are within *IMP-PACK-RADIUS* of IMP, on its storey."
  (let ((loc (location imp)))
    (loop for c across *creatures*
          count (and (not (eq c imp)) (typep c 'imp) (not (dead c)) (skittish-p c)
                     (let ((at (location c)))
                       (and (< (abs (- (vy at) (vy loc))) *shriek-rise*)
                            (< (+ (expt (- (vx at) (vx loc)) 2) (expt (- (vz at) (vz loc)) 2))
                               (expt *imp-pack-radius* 2))))))))

(defun courage (imp)
  (+ (/ (max 0 (health imp)) (max-health imp))
     (* *imp-pack-courage* (packmates imp))))

(defun test-courage (imp)
  "Break and run if IMP's courage has failed, once in its life."
  (when (and (skittish-p imp) (not (shrieked imp)) (not (dead imp)) (not (dormant-p imp))
             (< (courage imp) *imp-break-courage*))
    (setf (shrieked imp) T
          (shriek imp) *shriek-time*
          (fleeing imp) (+ *shriek-time* *imp-flee-time*)
          (cornered imp) 0.0
          (slot-yaw imp) NIL)
    (stop-walking imp *shriek-time*)))

(defun raise-alarm (imp)
  "IMP's shriek: every creature that can fight within *SHRIEK-RANGE*, on its storey, hunts."
  (let ((loc (location imp)))
    (loop for c across *creatures*
          for at = (location c)
          when (and (not (eq c imp)) (not (dead c)) (attacker-p c) (not (dormant-p c))
                    (< (abs (- (vy at) (vy loc))) *shriek-rise*)
                    (< (+ (expt (- (vx at) (vx loc)) 2) (expt (- (vz at) (vz loc)) 2))
                       (expt *shriek-range* 2)))
            do (when (<= (alert c) 0)
                 ;; As if it had just seen the player (NOTICE-PLAYER).
                 (setf (idle-timer c) (min (idle-timer c) *chase-pause*)
                       (replan-timer c) 0.0))
               (setf (alert c) (max (alert c) *shriek-alert-time*)))))

(defmethod creature-hurt ((imp imp) amount)
  (declare (ignore amount))
  (when (skittish-p imp)
    (when (airborne imp)
      (knock-down imp))
    (test-courage imp)))

;;; Running away.

(defun path-keeps-off-p (c parent feet closest grid)
  "True if the path to cell C (PARENT, from NAV-FLOOD) never comes within CLOSEST metres of FEET."
  (let ((cell (nav-cell-size grid)))
    (loop for k = c then (aref parent k)
          until (= k -1)
          always (multiple-value-bind (i j) (nav-unindex k grid)
                   (<= (expt closest 2)
                       (+ (expt (- (+ (nav-x0 grid) (* (+ i 0.5) cell)) (vx feet)) 2)
                          (expt (- (+ (nav-z0 grid) (* (+ j 0.5) cell)) (vz feet)) 2)))))))

(defun flee-path (imp)
  "A path for IMP to the cell within *FLEE-WALK* that is furthest from the player, along a walk
that comes no nearer them than it is now. NIL if there is none."
  (let ((grid *nav-grid*))
    (when grid
      (let* ((loc (ground-point imp))
             (r (body-radius imp))
             (h (sprite-height imp))
             (step (step-height imp))
             (feet (feet *player*))
             (now (player-distance imp))
             (closest (* 0.8 (min now 2.5))))
        (multiple-value-bind (si sj sk) (nav-nearest-fitting loc r h)
          (when si
            (multiple-value-bind (dist parent) (nav-flood si sj sk *flee-walk* r h step grid)
              (let* ((cell (nav-cell-size grid))
                     (spots (sort (loop for c from 0 below (length dist)
                                        when (<= *flee-min-walk* (aref dist c) *flee-walk*)
                                          collect (cons (multiple-value-bind (i j) (nav-unindex c grid)
                                                          (sqrt (+ (expt (- (+ (nav-x0 grid) (* (+ i 0.5) cell)) (vx feet)) 2)
                                                                   (expt (- (+ (nav-z0 grid) (* (+ j 0.5) cell)) (vz feet)) 2))))
                                                        c))
                                  #'> :key #'car))
                     (goal (loop for (away . c) in spots
                                 repeat 12
                                 when (and (< now away) (path-keeps-off-p c parent feet closest grid))
                                   return c)))
                (when goal
                  (let ((cells ()))
                    (loop for c = goal then (aref parent c)
                          until (= c -1)
                          do (push c cells))
                    (nav-smooth-path loc (nav-path-points (rest cells) grid) r h step grid)))))))))))

(defun flee (imp)
  "Set IMP running from the player: along FLEE-PATH, or a step straight back. True if it did."
  (let ((path (flee-path imp)))
    (cond (path
           (setf (path imp) path
                 (brain imp) :walking
                 (stuck imp) 0.0
                 (replan-timer imp) *chase-replan*)
           T)
          ((retreat imp)))))

(defun keep-fleeing (imp)
  "Go on running while IMP flees: true; NIL if it has nowhere to go, when it turns and fights."
  (cond ((and (eq (brain imp) :walking) (path imp)) T)
        ((< *flee-safe-distance* (player-distance imp))
         ;; Far enough: watch from here.
         (stop-walking imp 0.3)
         T)
        ((flee imp) T)
        (T
         (setf (fleeing imp) 0.0
               (cornered imp) *imp-cornered-time*)
         NIL)))

(defmethod chase-speed :around ((imp imp))
  (let ((speed (call-next-method)))
    (if (and speed (< 0 (fleeing imp)))
        (* speed *imp-flee-speed*)
        speed)))

;;; Thieving. The kind it carries is a pickup's (*PICKUP-KINDS*, pickups.lisp), dropped
;;; again where it dies.

(defun try-steal (imp)
  "Maybe snatch one of the player's items, the claw having landed. True if it did."
  (when (and (not (stolen imp)) (< (random 100 *roll-random*) *imp-steal-chance*))
    (let ((item (take-item *player*)))
      (when item
        (setf (stolen imp) (item-pickup-kind item)
              (fleeing imp) *thief-flee-time*
              (cornered imp) 0.0
              (slot-yaw imp) NIL)
        (flash-resource *player* :stolen)
        T))))

(defun seek-loot (imp)
  "Set IMP walking to the nearest pickup within *THIEF-SNIFF-RANGE* it can reach: true if it did."
  (let ((pickup (and *player* (< (player-distance imp) *thief-witness-range*)
                     (< (abs (- (vy (feet *player*)) (vy (location imp)))) *shriek-rise*)
                     (loose-pickup-near (location imp) *thief-sniff-range*))))
    (when (and pickup *nav-grid*)
      (let* ((at (location pickup))
             (to (vec (vx at) (pickup-ground pickup) (vz at)))
             (path (nav-path-to (ground-point imp) to (body-radius imp) (sprite-height imp) (step-height imp)
                                :max-walk (* 1.5 *thief-sniff-range*))))
        (when path
          (setf (path imp) path
                (brain imp) :walking
                (steal-target imp) pickup)
          T)))))

(defun reach-loot (imp)
  "Take the pickup IMP walks to once it is there; forget it if it is gone, or the walk is over."
  (let ((pickup (steal-target imp)))
    (cond ((or (taken pickup) (stolen imp) (hunting-p imp))
           (setf (steal-target imp) NIL))
          ((let ((loc (location imp)) (at (location pickup)))
             (and (< (+ (expt (- (vx at) (vx loc)) 2) (expt (- (vz at) (vz loc)) 2)) (expt *thief-reach* 2))
                  (< (abs (- (vy loc) (pickup-ground pickup))) 0.6)))
           (setf (taken pickup) T
                 (stolen imp) (pickup-kind pickup)
                 (steal-target imp) NIL))
          ((not (eq (brain imp) :walking))
           (setf (steal-target imp) NIL)))))

(defmethod wander ((imp imp))
  (unless (and (skittish-p imp) (not (stolen imp)) (seek-loot imp))
    (call-next-method)))

(defmethod creature-died ((imp imp))
  (when (stolen imp)
    (let* ((loc (location imp))
           (floor (or (and *nav-grid* (nav-floor-at (vx loc) (+ (vy loc) 0.1) (vz loc))) (vy loc))))
      (drop-loot (container imp) (stolen imp) (vx loc) floor (vz loc)))
    (setf (stolen imp) NIL))
  ;; Its pack loses heart.
  (loop for c across *creatures*
        when (and (typep c 'imp) (not (eq c imp)) (not (dead c))
                  (< (vdistance (location c) (location imp)) *imp-pack-radius*))
          do (test-courage c)))

(defmethod creature-revived ((imp imp))
  (setf (downed imp) 0.0
        (knocked imp) NIL
        (shriek imp) 0.0
        (shrieked imp) NIL
        (fleeing imp) 0.0
        (cornered imp) 0.0
        (stolen imp) NIL
        (steal-target imp) NIL))

;;; How it hunts.

(defmethod holds-back-p ((imp imp))
  (and (skittish-p imp)
       (or (< 0 (downed imp))
           (< 0 (shriek imp))
           (< 0 (fleeing imp))
           (and (stolen imp) (<= (cornered imp) 0)))))

(defmethod special-attack ((imp imp))
  (cond ((not (skittish-p imp)) (pounce imp))
        ((< 0 (downed imp)) (stop-walking imp (downed imp)) T)
        ((< 0 (shriek imp)) (stop-walking imp (shriek imp)) T)
        ((< 0 (fleeing imp)) (keep-fleeing imp))
        ((and (stolen imp) (<= (cornered imp) 0))
         (cond ((< (player-distance imp) *thief-keep-away*)
                (setf (fleeing imp) *thief-flee-time*
                      (slot-yaw imp) NIL)
                (keep-fleeing imp))
               (T
                (stop-walking imp 0.4)
                T)))
        (T (pounce imp))))

;; Hit and run: the claw, then a spring back out of reach, and another spot to come in from.
(defmethod release-attack ((imp imp))
  (if (not (skittish-p imp))
      (call-next-method)
      (progn
        (when (and (player-within-p imp (attack-reach imp))
                   (< (player-angle imp) (attack-arc imp))
                   (clear-path-p (location imp) (feet *player*) 1.0))
          (unless (hurt-player *player* (roll (attack-damage imp)) (location imp) :by imp)
            (try-steal imp)))
        (destructuring-bind (lo hi) *imp-spring-angle*
          (spring-from-player imp *imp-spring-speed*
                              (* (if (< (random 2) 1) -1 1) (+ lo (random (float (- hi lo) 0f0))))))
        (ban-slot imp))))

(defmethod keep-height :before ((imp imp) dt)
  (flet ((down (value) (max 0.0 (- value dt))))
    (setf (downed imp) (down (downed imp))
          (fleeing imp) (down (fleeing imp))
          (cornered imp) (down (cornered imp)))
    (when (< 0 (shriek imp))
      ;; A pale throb while it shrieks.
      (setf (flash imp) (max (flash imp) (* 0.7 *flash-time* (abs (sin (* 18.0 (shriek imp)))))))
      (when (<= (setf (shriek imp) (down (shriek imp))) 0)
        (unless (dead imp)
          (raise-alarm imp)))))
  (unless (dead imp)
    (when (steal-target imp)
      (reach-loot imp))
    (when (and (stolen imp) (not (and (loot-sprite imp) (container (loot-sprite imp)))))
      (setf (loot-sprite imp) (add-carried-loot imp (stolen imp))))))

(defmethod keep-height :after ((imp imp) dt)
  (declare (ignore dt))
  (when (and (eq (attack-kind imp) :leap) (or (airborne imp) (falling imp))
             (not (pounce-struck imp)) (not (dead imp)) *player* (< 0 (health *player*))
             (player-within-p imp *pounce-reach*))
    (pounce-strike imp)))

(defmethod show-own-pose ((imp imp) squash)
  (cond ((dead imp) (call-next-method))
        ((< 0 (downed imp))
         ;; Sprawled: the flinch's stagger, pressed down.
         (show-view-frame imp 'imp-hurt 1 0.8) T)
        ((< 0 (shriek imp))
         (show-view-frame imp 'imp-attack 1 squash) T)
        (T (call-next-method))))

;;; Packs: an imp a block spawns may bring one or two more. They are spread once the nav
;;; grid is built (SPREAD-PACKS, from BUILD-LEVEL), from a random state of their own, so the
;;; level and its other monsters don't change; a seed always gives the same packs, in the
;;; same order in *CREATURES*, which a save counts on.

(defvar *pack-leaders* (make-array 0 :adjustable T :fill-pointer T)
  "The imps blocks spawned in the level being built, in order. BUILD-LEVEL empties it.")

(defun pack-spot (leader claimed)
  "A free spot *PACK-SPACING* from LEADER, to its sides first, that an imp fits on and walks
straight to, clear of the level's creatures and the points in CLAIMED, or NIL."
  (let ((loc (location leader))
        (r (body-radius leader))
        (h (sprite-height leader)))
    (loop for n from 0 below 8
          for yaw = (+ (facing leader) (/ pi 2) (* (if (evenp n) 1 -1) (ceiling n 2) (/ pi 4)))
          for at = (vec (+ (vx loc) (* *pack-spacing* (sin yaw))) (vy loc) (- (vz loc) (* *pack-spacing* (cos yaw))))
          do (multiple-value-bind (i j k) (nav-nearest-fitting at r h :search 0 :reach 0.5)
               (when i
                 (let ((spot (nav-point i j k)))
                   (when (and (nav-line-clear-p loc spot r h (step-height leader))
                              (loop for c across *creatures*
                                    never (< (vdistance (location c) spot) (+ r (body-radius c) 0.1)))
                              (loop for p in claimed never (< (vdistance p spot) (+ r r 0.1))))
                     (return spot))))))))

(defun spread-packs (container seed)
  "Give the imps blocks spawned their packs, drawn from SEED."
  (let ((random (sb-ext:seed-random-state (logxor (or seed 0) #x1a7e)))
        (*nav-hazards* :avoid))
    (when *nav-grid*
      (loop for leader across *pack-leaders*
            for extra = (if (< (random 1.0 random) *imp-pack-chance*)
                            (if (< (random 1.0 random) *imp-pack-three*) 2 1)
                            0)
            unless (dead leader)
              do (let ((claimed ()))
                   (dotimes (n extra)
                     (let ((spot (pack-spot leader claimed)))
                       (when spot
                         (push spot claimed)
                         (spawn-creature (make-instance 'imp :location spot :facing (facing leader)) container)))))))
    (setf (fill-pointer *pack-leaders*) 0)))
