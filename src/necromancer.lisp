(in-package #:hexmaw)

;;; The necromancer and the skeletons it raises. The necromancer keeps its distance as
;;; the acolyte does, but has three abilities, each with its own wind-up and cooldown:
;;; it raises a skeleton from an intact corpse (a long channel a hit breaks), draws a
;;; grave circle under the player that strikes everything living in it a few seconds
;;; later (spells.lisp), and between them throws homing grave skulls. Raising tears the
;;; corpse apart, so each body gives one skeleton; a skeleton cut down leaves a pile of
;;; bones that can be raised again, unless the blow shattered it (its gibs).

;;; Abilities: a creature's attack slots, one set per ability. The necromancer's attack
;;; readers (ATTACK-FRAME-TIMES and the rest) answer for the ability it is using, so
;;; ATTACK runs any of them.

(defclass ability ()
  ((name :initarg :name :reader ability-name)
   (frame-times :initarg :frame-times :reader ability-frame-times
                :documentation "Seconds each frame of its animation shows, as ATTACK-FRAME-TIMES.")
   (hit-frame :initarg :hit-frame :initform 2 :reader ability-hit-frame
              :documentation "The frame it takes effect at, as ATTACK-HIT-FRAME.")
   (animation :initarg :animation :initform NIL :reader ability-animation
              :documentation "Frame animation it plays, one sequence per view, or NIL.")
   (spell :initarg :spell :initform NIL :reader ability-spell)
   (pause :initarg :pause :initform 0.8 :reader ability-pause
          :documentation "Seconds it stands after, as ATTACK-PAUSE.")
   (cooldown :initarg :cooldown :initform 0.0 :reader ability-cooldown
             :documentation "Seconds before it can be used again, from when it takes effect.")))

;;; The skeleton (SKELETON-WARRIOR: Trial already has a SKELETON, for skeletal animation).

(defparameter *skeleton-height* 1.8 "Skeleton height in metres, skull to feet.")

;; Sliced at 115 px tall, so its art pixels are the imp's size (96 px for 1.5 m).
(define-asset (hexmaw skeleton-turnaround) image
    #p"sprites/skeleton/turnaround.png"
  :min-filter :nearest :mag-filter :nearest)

;; It falls apart into a pile of bones, the corpse; played backwards, it gets up out of
;; one (SHOW-RISING). Front view only, the jolted skeleton in frame 1 115 px.
(define-fx-animation skeleton-death "sprites/skeleton/death" :fps 8 :size *skeleton-height*)
;; A loping walk, four frames per view; its cells are 119 px tall, the standing skeleton
;; 115 px. The frame follows the distance walked (STRIDE), so :FPS is unused.
(define-fx-animation skeleton-walk "sprites/skeleton/walk" :loop T :size (* *skeleton-height* 119/115))
;; An overhead chop: sword raised, the swing, the blow low, recover. Its cells are 153 px
;; tall to fit the raised sword. The frames run on ATTACK-FRAME-TIMES.
(define-fx-animation skeleton-attack "sprites/skeleton/attack" :size (* *skeleton-height* 153/115))
;; The flinch: jolt, then stagger, two frames per view over *STAGGER-TIME*.
(define-fx-animation skeleton-hurt "sprites/skeleton/hurt" :size (* *skeleton-height* 116/115))

(define-shader-entity skeleton-warrior (creature)
  ((texture :initform (// 'hexmaw 'skeleton-turnaround))
   (atlas :initform (read-atlas "sprites/skeleton/turnaround.lisp"))
   (sprite-height :initform *skeleton-height*)
   (walk-animation :initform 'skeleton-walk)
   (attack-animation :initform 'skeleton-attack)
   (hurt-animation :initform 'skeleton-hurt)
   (death-animation :initform 'skeleton-death)
   (bleeds :initform NIL)
   (undead :initform T)
   ;; Dry bones are brittle: most killing blows shatter them.
   (gibs :initform '((:bones (:head 0) 1 2 3 3 4 4 5 6 7 7)))
   (gib-overkill :initform 0.1)
   (attack-damage :initform '(7 11))
   (attack-reach :initform 0.7)
   (attack-frame-times :initform '(0.5 0.12 0.25 0.35))
   (attack-pause :initform 0.7)
   (walk-speed :initform 1.1)
   (chase-speed :initform 2.1)
   (wander-radius :initform 3.0)
   (knockback-scale :initform 0.8)
   (max-health :initform 20)))

(defun spawn-raised-skeleton (corpse container)
  "Raise a skeleton where CORPSE lies, getting up and already hunting. Returns it."
  (let* ((loc (location corpse))
         (feet (and *player* (feet *player*)))
         (skeleton (make-instance 'skeleton-warrior :location (vcopy loc) :summoned T
                                            :facing (if feet
                                                        (atan (- (vx feet) (vx loc)) (- (vz loc) (vz feet)))
                                                        (facing corpse)))))
    (setf (rising skeleton) (death-duration skeleton)
          (alert skeleton) *alert-time*)
    (spawn-creature skeleton container)
    (update-creature-look skeleton)
    skeleton))

;;; The necromancer.

(defparameter *necromancer-height* 2.0 "Necromancer height in metres, staff top to feet.")
(defparameter *raise-range* 10.0 "Metres from the necromancer a corpse can be raised.")
(defparameter *raise-light-color* (vec 0.3 1.4 0.4) "The glow over a corpse being raised, at its brightest.")
(defparameter *raise-light-radius* 3.0)
(defparameter *nova-range* 9.0 "Metres from the necromancer the player can be for it to draw its grave circle.")

;; Sliced at 128 px tall for its 2 m, staff included, at the imp's art pixel size.
(define-asset (hexmaw necromancer-turnaround) image
    #p"sprites/necromancer/turnaround.png"
  :min-filter :nearest :mag-filter :nearest)

;; It falls face down beside its staff. Front view only; its cells are 131 px tall, the
;; jolted necromancer in frame 1 128 px, staff and all.
(define-fx-animation necromancer-death "sprites/necromancer/death" :fps 9 :size (* *necromancer-height* 131/128))
;; A shuffling walk leaning on the staff, four frames per view; its cells are 131 px tall,
;; the standing necromancer 128 px.
(define-fx-animation necromancer-walk "sprites/necromancer/walk" :loop T :size (* *necromancer-height* 131/128))
;; The raise and the grave circle: the staff raised high, the free hand flaring green (the
;; frame the raise's channel holds), the hand thrust out, recover. Its cells are 170 px
;; tall to fit the raised staff.
(define-fx-animation necromancer-cast "sprites/necromancer/cast" :size (* *necromancer-height* 170/128))
;; The grave skull: the staff swung back, then forward with the skull on it blazing (the
;; release), follow-through, recover. Cells 142 px tall.
(define-fx-animation necromancer-thrust "sprites/necromancer/thrust" :size (* *necromancer-height* 142/128))
;; The flinch: jolt, then stagger, two frames per view over *STAGGER-TIME*.
(define-fx-animation necromancer-hurt "sprites/necromancer/hurt" :size (* *necromancer-height* 130/128))

(defun necromancer-abilities ()
  (list (make-instance 'ability :name :skull :spell 'grave-skull :animation 'necromancer-thrust
                                :frame-times '(0.35 0.15 0.2 0.3) :hit-frame 1 :pause 1.0)
        ;; The channel's held frame is the warning: two seconds to break it with a hit.
        (make-instance 'ability :name :raise :animation 'necromancer-cast
                                :frame-times '(0.3 1.7 0.25 0.35) :hit-frame 2 :pause 0.8 :cooldown 7.0)
        (make-instance 'ability :name :nova :spell 'grave-spikes :animation 'necromancer-cast
                                :frame-times '(0.3 0.4 0.25 0.35) :hit-frame 2 :pause 1.0 :cooldown 14.0)))

(define-shader-entity necromancer (creature)
  ((texture :initform (// 'hexmaw 'necromancer-turnaround))
   (atlas :initform (read-atlas "sprites/necromancer/turnaround.lisp"))
   (sprite-height :initform *necromancer-height*)
   (walk-animation :initform 'necromancer-walk)
   (hurt-animation :initform 'necromancer-hurt)
   (death-animation :initform 'necromancer-death)
   (gibs :initform '((:flesh 0 0 1 1 2 3 4 5 6 6 7 7)))
   (gib-scale :initform 1.15)
   (abilities :initform (necromancer-abilities) :reader abilities)
   (ability :initform NIL :accessor current-ability
            :documentation "The ability it is using, or last used.")
   (cooldowns :initform (list :raise 0.0 :nova 0.0) :accessor cooldowns
              :documentation "Seconds before each ability can be used again, by name.")
   (raise-target :initform NIL :accessor raise-target :documentation "The corpse it is raising.")
   (raise-lamp :initform NIL :accessor raise-lamp)
   (attack-range :initform 12.0)
   (keep-away :initform 5.0)
   ;; The staff is in its right hand.
   (cast-offset :initform 0.35)
   (walk-speed :initform 1.0)
   (chase-speed :initform 1.6)
   (wander-radius :initform 2.0)
   (max-health :initform 35)))

(defmethod initialize-instance :after ((necromancer necromancer) &key)
  (setf (current-ability necromancer) (find-ability necromancer :skull)))

(defun find-ability (necromancer name)
  (find name (abilities necromancer) :key #'ability-name))

;; Only the current animation's texture is staged with the scene; stage every ability's.
(defmethod stage :after ((necromancer necromancer) (area staging-area))
  (dolist (ability (abilities necromancer))
    (when (ability-animation ability)
      (stage (animation-texture (find-fx-animation (ability-animation ability))) area))))

(defmethod attack-frame-times ((n necromancer)) (ability-frame-times (current-ability n)))
(defmethod attack-hit-frame ((n necromancer)) (ability-hit-frame (current-ability n)))
(defmethod attack-animation ((n necromancer)) (ability-animation (current-ability n)))
(defmethod attack-pause ((n necromancer)) (ability-pause (current-ability n)))
;; The raise has no spell; the skull's stands for it then, so it still counts as an
;; attacker (ATTACKER-P) and goes on hunting.
(defmethod attack-spell ((n necromancer))
  (or (ability-spell (current-ability n)) (ability-spell (first (abilities n)))))
(defmethod ranged-p ((n necromancer)) T)
(defmethod spares-p ((n necromancer) target) (undead target))

(defun ready-p (necromancer name)
  (<= (getf (cooldowns necromancer) name) 0))

(defun raisable-p (corpse)
  "True if CORPSE can be raised: dead and done falling, whole, and of flesh or bone."
  (and (dead corpse)
       (not (gibbed corpse))
       (gibs corpse)
       (< (death-duration corpse) (dead corpse))))

(defun corpse-to-raise (necromancer)
  "The nearest corpse NECROMANCER can raise: within *RAISE-RANGE* and in sight."
  (let ((loc (location necromancer))
        (best NIL)
        (best-distance *raise-range*))
    (loop for c across *creatures*
          for at = (location c)
          for d = (sqrt (+ (expt (- (vx at) (vx loc)) 2) (expt (- (vz at) (vz loc)) 2)))
          when (and (< d best-distance) (raisable-p c)
                    (< (abs (- (vy at) (vy loc))) 1.0)
                    (clear-path-p loc at 1.0))
            do (setf best c best-distance d))
    best))

(defun start-ability (necromancer name)
  (setf (current-ability necromancer) (find-ability necromancer name))
  (start-attack necromancer))

(defmethod hunt-from-range ((necromancer necromancer))
  "Back off from a player too close; raise a corpse if one is in reach; draw the grave
circle under a player in range and sight; else throw skulls, or close in."
  (let ((distance (player-distance necromancer))
        (corpse NIL))
    (cond ((and (< distance (keep-away necromancer)) (retreat necromancer)))
          ((and (ready-p necromancer :raise) (setf corpse (corpse-to-raise necromancer)))
           (setf (raise-target necromancer) corpse)
           (start-ability necromancer :raise))
          ((and (ready-p necromancer :nova) (< distance *nova-range*)
                (clear-path-p (location necromancer) (feet *player*) (cast-height necromancer)))
           (start-ability necromancer :nova))
          ((and (< distance (attack-range necromancer))
                (clear-path-p (location necromancer) (feet *player*) (cast-height necromancer)))
           (start-ability necromancer :skull))
          (T (chase necromancer)))))

(defmethod face-attack-target ((necromancer necromancer) dt)
  (let ((corpse (raise-target necromancer)))
    (if (and corpse (eq :raise (ability-name (current-ability necromancer))))
        (let ((loc (location necromancer))
              (at (location corpse)))
          (turn-to necromancer (atan (- (vx at) (vx loc)) (- (vz loc) (vz at))) dt))
        (face-player necromancer dt))))

(defun raise-corpse (necromancer)
  "Tear the corpse NECROMANCER channelled into apart, and stand a skeleton up out of it."
  (let ((corpse (raise-target necromancer)))
    (setf (raise-target necromancer) NIL)
    ;; Another necromancer, or a revival, may have got there first.
    (when (and corpse (raisable-p corpse) (container necromancer))
      (tear-apart corpse :from (location necromancer))
      (spawn-raised-skeleton corpse (container necromancer)))))

(defun cast-grave-circle (necromancer)
  "Draw NECROMANCER's grave circle on the floor under the player as they stand now."
  (let* ((feet (feet *player*))
         (floor (or (and *nav-grid* (nav-floor-at (vx feet) (vy feet) (vz feet))) (vy feet))))
    (cast-spell (find-spell (ability-spell (current-ability necromancer)))
                (vec (vx feet) floor (vz feet)) (vec 0 0 -1) (container necromancer)
                :caster necromancer)))

(defmethod release-attack ((necromancer necromancer))
  (let ((ability (current-ability necromancer)))
    (ecase (ability-name ability)
      (:skull (release-attack-spell necromancer))
      (:raise (raise-corpse necromancer))
      (:nova (cast-grave-circle necromancer)))
    (when (< 0 (ability-cooldown ability))
      (setf (getf (cooldowns necromancer) (ability-name ability)) (ability-cooldown ability)))))

(defun channelling-p (necromancer)
  "True while NECROMANCER is in the middle of raising a corpse."
  (and (eq (brain necromancer) :attacking)
       (not (dead necromancer))
       (raise-target necromancer)
       (eq :raise (ability-name (current-ability necromancer)))))

(defun update-raise-glow (necromancer)
  "Light and stir the corpse being raised, brighter as the channel goes on; put the light
out when the channel ends or breaks."
  (let ((lamp (raise-lamp necromancer))
        (corpse (raise-target necromancer)))
    (cond ((channelling-p necromancer)
           (let* ((at (location corpse))
                  (k (min 1.0 (/ (attack-time necromancer) (attack-hit-time necromancer)))))
             (unless (and lamp (find lamp *lamps*))
               (setf lamp (add-lamp (vec (vx at) (+ (vy at) 0.5) (vz at)) *raise-light-color*
                                    *raise-light-radius* :flicker 0.3)
                     (raise-lamp necromancer) lamp))
             (let ((color (color lamp)))
               (setf (vx color) (* k (vx *raise-light-color*))
                     (vy color) (* k (vy *raise-light-color*))
                     (vz color) (* k (vz *raise-light-color*))))
             (setf (stirring corpse) 0.1)))
          (T
           ;; A hit broke the channel: the corpse stays as it was, to be tried again.
           (when (and corpse (not (eq (brain necromancer) :attacking)))
             (setf (raise-target necromancer) NIL))
           (when lamp
             (remove-lamp lamp)
             (setf (raise-lamp necromancer) NIL))))))

(define-handler (necromancer tick :after) (dt)
  (unless (frozen-p)
    (loop for (name left) on (cooldowns necromancer) by #'cddr
          do (setf (getf (cooldowns necromancer) name) (max 0.0 (- left dt))))
    (update-raise-glow necromancer)))
