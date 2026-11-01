(in-package #:hexmaw)

;;; The gale wraith: a hooded figure of rags that floats just off the floor, keeps its
;;; distance and fights with the wind. It has two abilities. The tornado (vortex.lisp) takes
;;; a long cast: a sign (GALE-SIGN) draws itself on the floor under the player as they stood
;;; when it began, and the tornado forms on it at the release, so there is time to leave.
;;; Hurting it into a flinch breaks the cast, and sign and tornado are gone. Between tornadoes
;;; it throws gusts, weak but lifting the player toward its tornado if it has one. It has
;;; no walk: its rags hide its legs, and it glides in the standing pose. Its own tornado
;;; takes it as readily as anything else.

(defparameter *wraith-height* 1.8 "Gale wraith height in metres.")
(defparameter *wraith-hover* 0.6 "Metres over the floor it floats, low enough for the sword.")
(defparameter *tempest-cast-time* 1.5 "Seconds from the start of its tornado's cast to its release.")
(defparameter *tempest-retry* 3.0 "Seconds before it tries again after a broken cast.")
(defparameter *tempest-cooldown* 14.0 "Seconds from one tornado's release to the next cast.")
(defparameter *gust-shove* 7.0 "Speed in m/s a gust throws the player.")
(defparameter *gust-lift* 3.5 "Speed in m/s it throws them up: a shove on the floor dies at once.")
(defparameter *gust-vortex-reach* 12.0 "Metres within which its tornado draws the gust's shove toward it.")

(defparameter *sign-light-color* (vec 1.2 0.8 2.2) "Its lamp's colour just before the tornado forms.")
(defparameter *sign-light-radius* 6.0)
(defparameter *sign-dust* 0.4 "How strongly the column of dust rising from the sign shows.")
(defparameter *sign-dust-height* '(0.5 2.4) "Metres the column rises from and to.")
(defparameter *sign-aurora-colors*
  (list (vec 0.55 0.3 1.0) (vec 0.8 0.55 1.0) (vec 0.35 0.45 1.0) (vec 0.25 0.12 0.6) (vec 0.85 0.75 1.0))
  "The colours of the aurora round its rim, as *GRAVE-AURORA-COLORS*: storm violets.")
(defparameter *sign-aurora-spin* 0.45 "Turns a second its aurora's streaks run round the rim. Read when a sign is lit.")
(defparameter *sign-aurora-twist* 0.2 "Whole turns they lean, foot to top. Read when a sign is lit.")

(define-fx-animation gale-sign "sprites/gale/sign" :loop T :size (/ 264 64.0))
;; Grit on the wind, on the ogre's dust.
(define-fx-animation gust-flight "sprites/ogre/dust" :fps 14 :loop T :size 0.7)

(define-spell gust (:delivery :projectile :projectile-speed 8.0 :lifetime 3.0
                    :projectile-animation 'gust-flight :impact-animation 'ogre-dust
                    :light-color (vec 0.4 0.3 0.7) :light-radius 3.0)
  (:damage :magnitude '(1 3))
  (:gust :magnitude '(7 7)))

;; Gather, both arms raised with lightning on the hands (what the tornado's cast holds),
;; release, recover. Its cells are 143 px tall to fit the raised arms, the floating wraith 115.
(define-fx-animation wraith-cast "sprites/wraith/cast" :size (* *wraith-height* 143/115))
;; The flinch: jolt, then stagger, two frames per view over *STAGGER-TIME*.
(define-fx-animation wraith-hurt "sprites/wraith/hurt" :size (* *wraith-height* 116/115))
;; The wind dies and the rags settle into an empty heap, the corpse. Front view only; its
;; cells are 114 px tall, the jolted wraith in frame 1 at the turnaround's scale.
(define-fx-animation wraith-death "sprites/wraith/death" :fps 9 :size (* *wraith-height* 114/115))

(defun wraith-abilities ()
  (list (make-instance 'ability :name :gust :spell 'gust :animation 'wraith-cast
                                :frame-times '(0.3 0.25 0.25 0.3) :hit-frame 2 :pause 1.2)
        (make-instance 'ability :name :tempest :spell 'tempest :animation 'wraith-cast
                                :frame-times (list 0.3 (- *tempest-cast-time* 0.3) 0.25 0.35)
                                :hit-frame 2 :pause 1.0 :cooldown *tempest-cooldown*)))

;; Sliced at 115 px tall, so its art pixels are the imp's size (96 px for 1.5 m).
(define-asset (hexmaw wraith-turnaround) image
    #p"sprites/wraith/turnaround.png"
  :min-filter :nearest :mag-filter :nearest)

(define-shader-entity gale-wraith (ability-user flyer)
  ((texture :initform (// 'hexmaw 'wraith-turnaround))
   (atlas :initform (read-atlas "sprites/wraith/turnaround.lisp"))
   (sprite-height :initform *wraith-height*)
   (hurt-animation :initform 'wraith-hurt)
   (death-animation :initform 'wraith-death)
   (abilities :initform (wraith-abilities))
   (cooldowns :initform (list :tempest 0.0))
   (hover-height :initform *wraith-hover*)
   (attack-range :initform 12.0)
   (keep-away :initform 6.0)
   (cast-offset :initform 0.25)
   (walk-speed :initform 1.2)
   (chase-speed :initform 2.0)
   (wander-radius :initform 2.5)
   (pain-chance :initform 60)
   (gibs :initform '((:flesh 0 1 2 4 5 6 7)))
   (max-health :initform 40)
   (tempest-point :initform (vec 0 0 0) :reader tempest-point
                  :documentation "Where on the floor the tornado it is casting will form.")))

;; A cast, not a flyer's dive; it hangs where it is meanwhile.
(defmethod attack-step ((wraith gale-wraith) dt)
  (attack wraith dt))

(defun own-vortex (wraith)
  (find wraith *vortices* :key #'caster))

(defun begin-tempest (wraith)
  "Start casting the tornado at the floor under the player, marked there by a sign."
  (v<- (tempest-point wraith) (floor-under (feet *player*)))
  (setf (getf (cooldowns wraith) :tempest) *tempest-retry*)
  (start-ability wraith :tempest)
  (enter (make-instance 'gale-sign :caster wraith :centre (vcopy (tempest-point wraith))
                                   :location (vcopy (tempest-point wraith))
                                   :animation (find-fx-animation 'gale-sign))
         (container wraith)))

(defmethod hunt-from-range ((wraith gale-wraith))
  "Back off from a player too close; with one in range and sight, cast a tornado at them
if none is up and the player is on a floor to lay the sign on, else throw a gust; or close in."
  (let* ((distance (player-distance wraith))
         (seen (and (< distance (attack-range wraith))
                    (clear-path-p (location wraith) (feet *player*) (cast-height wraith)))))
    (cond ((and (< distance (keep-away wraith)) (retreat wraith)))
          ((and seen (ready-p wraith :tempest) (not (own-vortex wraith))
                (not (swimming *player*)) (not (whirl *player*)))
           (begin-tempest wraith))
          (seen (start-ability wraith :gust))
          (T (chase wraith)))))

(defmethod release-attack ((wraith gale-wraith))
  (let ((ability (current-ability wraith)))
    (ecase (ability-name ability)
      (:gust (release-attack-spell wraith))
      (:tempest
       (cast-spell (find-spell 'tempest) (tempest-point wraith) (vec 0 0 -1) (container wraith) :caster wraith)
       (setf (getf (cooldowns wraith) :tempest) (ability-cooldown ability))))))

(define-handler (gale-wraith tick :after) (dt)
  (unless (frozen-p)
    (run-cooldowns gale-wraith dt)))

(defun casting-tempest-p (wraith)
  "True while WRAITH's tornado has yet to be released. A flinch, its death or a vortex
catching it all end that by stopping the attack."
  (and wraith
       (not (dead wraith))
       (eq :tempest (ability-name (current-ability wraith)))
       (winding-up-p wraith)))

;;; The sign.

(define-shader-entity gale-sign (fx-sprite)
  ((caster :initarg :caster :initform NIL :reader caster)
   (centre :initarg :centre :reader centre)
   (lamp :initform NIL :accessor sign-lamp)
   (funnel :initform NIL :accessor sign-funnel)
   (aurora :initform NIL :accessor sign-aurora)))

(defmethod initialize-instance :after ((sign gale-sign) &key)
  ;; Flat on the floor, facing up, just off it.
  (!qfrom-angle (orientation sign) +vx+ #.(float (- (/ pi 2)) 0f0))
  (incf (vy (location sign)) 0.01))

(defun light-sign (sign)
  (let ((c (centre sign)))
    (setf (sign-funnel sign) (make-instance 'funnel :centre c)
          (sign-aurora sign) (make-instance 'aurora :centre c
                                                    :radius (getf (animation-atlas (sprite-animation sign)) :radius)
                                                    :colors *sign-aurora-colors*
                                                    :spin *sign-aurora-spin* :twist *sign-aurora-twist*)
          (sign-lamp sign) (add-lamp (vec (vx c) (+ (vy c) 0.8) (vz c)) *sign-light-color* *sign-light-radius*
                                     :flicker 0.15))
    (enter (sign-funnel sign) (container sign))
    (enter (sign-aurora sign) (container sign))))

(defmethod leave :after ((sign gale-sign) container)
  (when (sign-funnel sign)
    (despawn (sign-funnel sign))
    (setf (sign-funnel sign) NIL))
  (when (sign-aurora sign)
    (despawn (sign-aurora sign))
    (setf (sign-aurora sign) NIL))
  (when (sign-lamp sign)
    (remove-lamp (sign-lamp sign))
    (setf (sign-lamp sign) NIL)))

;; Its own tick, not FX-SPRITE's: the frame follows the cast, and it lies flat.
(define-handler (gale-sign tick) (dt)
  (when (and (null (sign-lamp gale-sign)) (container gale-sign))
    (light-sign gale-sign))
  (unless (frozen-p)
    (incf (age gale-sign) dt)
    (unless (casting-tempest-p (caster gale-sign))
      (despawn gale-sign)))
  (let* ((atlas (animation-atlas (sprite-animation gale-sign)))
         (count (getf atlas :frames))
         (k (min 1.0 (/ (age gale-sign) *tempest-cast-time*)))
         (lamp (sign-lamp gale-sign))
         (funnel (sign-funnel gale-sign))
         (aurora (sign-aurora gale-sign)))
    (strip-uv (frame-uv gale-sign) atlas (sign-frame (age gale-sign) *tempest-cast-time* count) count)
    (when aurora
      (raise-aurora aurora (age gale-sign) *tempest-cast-time* k))
    (when lamp
      (let ((color (color lamp)))
        (setf (vx color) (* k (vx *sign-light-color*))
              (vy color) (* k (vy *sign-light-color*))
              (vz color) (* k (vz *sign-light-color*)))))
    (when funnel
      (setf (funnel-strength funnel) (* k *sign-dust*)
            (funnel-height funnel) (ramp *sign-dust-height* k)))))

;;; The gust.

(defmethod apply-effect ((kind (eql :gust)) effect (target creature) source)
  (push-creature target (effect-direction source target) (float (roll (effect-magnitude effect)) 0f0)))

(defmethod apply-effect ((kind (eql :gust)) effect (target player) (source spell-projectile))
  (let* ((feet (feet target))
         (flight (projectile-velocity source))
         (vortex (and (caster source) (not (eq (caster source) target)) (own-vortex (caster source))))
         (c (and vortex (centre vortex)))
         (toward (and c (< (+ (expt (- (vx c) (vx feet)) 2) (expt (- (vz c) (vz feet)) 2))
                           (expt *gust-vortex-reach* 2))))
         (dx (if toward (- (vx c) (vx feet)) (vx flight)))
         (dz (if toward (- (vz c) (vz feet)) (vz flight)))
         (len (sqrt (+ (* dx dx) (* dz dz))))
         (k (if (shield-blocks-p target (v- (location source) flight)) *block-shove-scale* 1.0))
         (speed (* k (float (roll (effect-magnitude effect)) 0f0)))
         (vel (velocity target)))
    (when (< 1f-4 len)
      (incf (vx vel) (float (* speed (/ dx len)) 0f0))
      (incf (vz vel) (float (* speed (/ dz len)) 0f0)))
    (setf (vy vel) (max (vy vel) (float (* k *gust-lift*) 0f0)))))
