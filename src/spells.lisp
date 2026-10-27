(in-package #:hexmaw)

;;; Daggerfall-style spells. A spell is a delivery (how it reaches its target)
;;; plus a list of effects. Each effect has a kind, a magnitude range, a duration,
;;; an area and a target type, and the spell's cost is derived from that
;;; composition, so a spellmaker can later build new spells from the same parts.
;;; What an effect kind does is a method on APPLY-EFFECT.

(defclass effect ()
  ((kind :initarg :kind :reader effect-kind
         :documentation "Keyword naming what the effect does: :DAMAGE, :KNOCKBACK, ...")
   (magnitude :initarg :magnitude :initform '(1 1) :reader effect-magnitude
              :documentation "(MIN MAX); each application rolls an integer in that range.")
   (duration :initarg :duration :initform 0 :reader effect-duration
             :documentation "Seconds; 0 is instant. Not used yet.")
   (area :initarg :area :initform 0 :reader effect-area
         :documentation "Radius in metres; 0 is a single target. Not used yet.")
   (target-type :initarg :target-type :initform :target :reader effect-target-type
                :documentation ":SELF, :TOUCH or :TARGET (whatever the delivery hits).")))

(defclass spell ()
  ((name :initarg :name :reader spell-name)
   (delivery :initarg :delivery :initform :projectile :reader spell-delivery)
   (projectile-speed :initarg :projectile-speed :initform 20.0 :reader projectile-speed)
   (projectile-color :initarg :projectile-color :initform (vec 1.0 0.55 0.15) :reader projectile-color)
   (effects :initarg :effects :reader spell-effects)))

(defvar *spells* (make-hash-table :test 'eq))

(defun find-spell (name)
  (or (gethash name *spells*) (error "No spell named ~s." name)))

(defmacro define-spell (name (&rest options) &body effects)
  "Define spell NAME. OPTIONS are SPELL initargs; each effect is (KIND &rest EFFECT-INITARGS):

  (define-spell bolt (:delivery :projectile :projectile-speed 20.0)
    (:damage :magnitude '(6 10))
    (:knockback :magnitude '(4 4)))"
  `(setf (gethash ',name *spells*)
         (make-instance 'spell :name ',name ,@options
                               :effects (list ,@(loop for (kind . args) in effects
                                                      collect `(make-instance 'effect :kind ,kind ,@args))))))

;;; Cost: each effect's base cost times its average magnitude, scaled up by
;;; duration and area; a spell costs the sum, rounded up.

(defparameter *effect-base-costs* '(:damage 1.5 :knockback 0.5)
  "Mana per point of average magnitude, per effect kind. Unlisted kinds cost 1.")

(defun effect-cost (effect)
  (destructuring-bind (lo hi) (effect-magnitude effect)
    (* (getf *effect-base-costs* (effect-kind effect) 1.0)
       (/ (+ lo hi) 2)
       (+ 1 (/ (effect-duration effect) 5))
       (+ 1 (effect-area effect)))))

(defun spell-cost (spell)
  (ceiling (reduce #'+ (spell-effects spell) :key #'effect-cost)))

(defun roll (magnitude)
  (destructuring-bind (lo hi) magnitude
    (+ lo (random (1+ (- hi lo))))))

;;; Effects.

(defgeneric apply-effect (kind effect target source)
  (:documentation "Apply EFFECT, whose kind is KIND, to TARGET. SOURCE is what delivered
it (a SPELL-PROJECTILE for projectile spells)."))

(defmethod apply-effect (kind effect target source)
  (v:warn :hexmaw "No ~s effect for ~a; ignored." kind target))

(defmethod apply-effect ((kind (eql :damage)) effect (target creature) source)
  (hurt target (roll (effect-magnitude effect))))

(defun apply-spell (spell target source)
  (dolist (effect (spell-effects spell))
    (when (eq :target (effect-target-type effect))
      (apply-effect (effect-kind effect) effect target source))))

;;; Projectile delivery.

(defparameter *projectile-lifetime* 3.0 "Seconds before a projectile that hit nothing vanishes.")
(defparameter *projectile-size* 0.18 "Diameter in metres.")

(define-shader-entity spell-projectile (vertex-entity colored-entity transformed-entity listener)
  ((vertex-array :initform (// 'trial 'unit-sphere))
   (spell :initarg :spell :initform NIL :reader spell)
   (projectile-velocity :initform (vec 0 0 0) :reader projectile-velocity)
   (age :initform 0.0 :accessor age)))

;; Knockback pushes along the direction the projectile was flying.
(defmethod apply-effect ((kind (eql :knockback)) effect (target creature) (source spell-projectile))
  (push-creature target (projectile-velocity source) (float (roll (effect-magnitude effect)) 0f0)))

(defun launch-projectile (spell origin direction container)
  "Fire SPELL from ORIGIN along unit vector DIRECTION."
  (let ((size (float *projectile-size* 0f0))
        (color (projectile-color spell))
        (projectile (make-instance 'spell-projectile :spell spell :location (vcopy origin))))
    (setf (scaling projectile) (vec size size size)
          (color projectile) (vec4 (vx color) (vy color) (vz color) 1))
    (v<- (projectile-velocity projectile) direction)
    (nv* (projectile-velocity projectile) (float (projectile-speed spell) 0f0))
    (enter projectile container)))

(defun remove-projectile (projectile)
  (when (container projectile)
    (leave projectile (container projectile))))

(define-handler (spell-projectile tick) (dt)
  (unless (frozen-p)
    (let* ((loc (location spell-projectile))
           (r (* 0.5 (float *projectile-size* 0f0))))
      (nv+* loc (projectile-velocity spell-projectile) dt)
      (incf (age spell-projectile) dt)
      (let ((victim (creature-at loc r)))
        (cond (victim
               (apply-spell (spell spell-projectile) victim spell-projectile)
               (remove-projectile spell-projectile))
              ((or (solid-overlapping (vx loc) (- (vy loc) r) (vz loc) r (* 2 r))
                   (< *projectile-lifetime* (age spell-projectile)))
               (remove-projectile spell-projectile)))))))

(defun cast-spell (spell origin direction container)
  "Deliver SPELL from ORIGIN along unit vector DIRECTION. Mana is the caster's business."
  (ecase (spell-delivery spell)
    (:projectile (launch-projectile spell origin direction container))))

;;; The spells.

(define-spell bolt (:delivery :projectile :projectile-speed 20.0 :projectile-color (vec 1.0 0.55 0.15))
  (:damage :magnitude '(6 10))
  (:knockback :magnitude '(4 4)))
