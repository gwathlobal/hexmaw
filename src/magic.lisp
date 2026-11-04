(in-package #:hexmaw)

;;; What the effects the spellforge offers do (*EFFECT-KINDS*, spells.lisp), and the
;;; statuses they leave. A status is what an effect with a duration leaves on an actor
;;; (the AFFLICTED mixin, creature.lisp): damage or healing a second, a slow, a ward. An
;;; actor has at most one of each kind; a second keeps the stronger magnitude and the
;;; longer time. Statuses tick in the actor's own tick (UPDATE-STATUSES), changing their
;;; slots in place, since that runs every frame.
;;;
;;; Elements: fire is plain damage; frost also chills (a short slow); shock also staggers
;;; more (its pain bonus). A creature may resist an element (*ELEMENT-RESISTANCES*).

(defparameter *status-tick* 0.5 "Seconds between the blows of damage or healing over time.")
(defparameter *frost-chill* 20 "Percent a frost hit slows what it strikes, for *FROST-CHILL-TIME*.")
(defparameter *frost-chill-time* 2.0)
(defparameter *shock-pain-bonus* 20 "Percent a shock hit adds to the pain roll.")
(defparameter *drain-share* 0.5 "Fraction of the health a drain takes that its caster gets.")
(defparameter *slowest* 0.4 "The least fraction of its speed a slow leaves anything.")
(defparameter *element-resistances*
  '((acolyte :fire 0.5) (skeleton-warrior :frost 0.5) (gale-wraith :shock 0.5))
  "(CLASS ELEMENT FRACTION): CLASS and its subclasses take FRACTION less of ELEMENT's damage.")
(defparameter *element-tints*
  '(:fire (1.0 0.45 0.1) :frost (0.45 0.75 1.0) :shock (0.85 0.7 1.0) :arcane (0.8 0.4 1.0))
  "Colour a creature takes on while a status of that element is on it.")
(defparameter *status-tint* 0.3 "How strongly a status tints a creature, at most.")

(defclass status ()
  ((kind :initarg :kind :reader status-kind :documentation ":DAMAGE, :HEAL, :SLOW or :WARD.")
   (element :initarg :element :initform NIL :accessor status-element)
   (magnitude :initarg :magnitude :accessor status-magnitude
              :documentation "Damage or health a second, percent slower, or ward points left.")
   (left :initarg :left :accessor status-left :documentation "Seconds left.")
   (timer :initarg :timer :initform 0.0 :accessor status-timer
          :documentation "Seconds to its next blow, for damage or healing over time.")
   (owed :initarg :owed :initform 0.0 :accessor status-owed
         :documentation "The part of a point of damage or healing not yet dealt.")
   (caster :initarg :caster :initform NIL :accessor status-caster
           :documentation "Who put it on: the death screen's killer, a drain's beneficiary.")))

(defun status-of (actor kind)
  (find kind (statuses actor) :key #'status-kind))

(defun afflict (actor kind magnitude duration &key element caster)
  "Put a status of KIND on ACTOR for DURATION seconds, or strengthen the one it has."
  (let ((status (status-of actor kind)))
    (cond (status
           (setf (status-magnitude status) (max (status-magnitude status) magnitude)
                 (status-left status) (max (status-left status) (float duration 0f0)))
           (when element
             (setf (status-element status) element))
           (when caster
             (setf (status-caster status) caster)))
          (T
           (push (make-instance 'status :kind kind :magnitude magnitude :left (float duration 0f0)
                                        :element element :caster caster)
                 (statuses actor))))))

(defgeneric status-blow (actor kind amount status)
  (:documentation "Deal AMOUNT, a whole number, of STATUS's damage or healing to ACTOR."))

(defun update-statuses (actor dt)
  "Run ACTOR's statuses for DT seconds: deal what is due, and drop the spent ones."
  (let ((spent NIL))
    (dolist (status (statuses actor))
      (decf (status-left status) dt)
      (when (member (status-kind status) '(:damage :heal))
        (decf (status-timer status) dt)
        (when (<= (status-timer status) 0)
          (incf (status-timer status) *status-tick*)
          (let* ((amount (+ (status-owed status) (* (status-magnitude status) *status-tick*)))
                 (whole (floor amount)))
            (setf (status-owed status) (- amount whole))
            (when (< 0 whole)
              (status-blow actor (status-kind status) whole status)))))
      (when (<= (status-left status) 0)
        (setf spent T)))
    (when spent
      (setf (statuses actor) (delete-if (lambda (status) (<= (status-left status) 0)) (statuses actor))))))

(defun slow-factor (actor)
  "Fraction of its speed ACTOR's slow leaves it, 1 with none."
  (let ((slow (status-of actor :slow)))
    (if slow (max *slowest* (- 1.0 (/ (status-magnitude slow) 100.0))) 1.0)))

(defun absorb-ward (actor amount)
  "The part of AMOUNT damage that gets past ACTOR's ward, which loses the rest."
  (let ((ward (status-of actor :ward)))
    (if (and ward (< 0 amount))
        (let ((taken (min amount (status-magnitude ward))))
          (decf (status-magnitude ward) taken)
          (when (<= (status-magnitude ward) 0)
            (setf (status-left ward) 0.0))
          (- amount taken))
        amount)))

(defun status-tint (creature tint)
  "Tint CREATURE toward the element of a status on it, if its hit flash is weaker."
  (let ((status (find-if (lambda (s) (or (status-element s) (eq :slow (status-kind s)))) (statuses creature))))
    (when status
      (let ((rgb (getf *element-tints* (or (status-element status) :arcane)))
            (k (* *status-tint* (+ 0.75 (* 0.25 (sin (* 6.0 (status-left status))))))))
        (when (and rgb (< (vw tint) k))
          (setf (vx tint) (first rgb) (vy tint) (second rgb) (vz tint) (third rgb)
                (vw tint) k))))))

(defun resisted (target element amount)
  "AMOUNT of ELEMENT's damage, less what TARGET resists of it."
  (let ((entry (find-if (lambda (e) (and (eq element (second e)) (typep target (first e))))
                        *element-resistances*)))
    (if entry (max 1 (round (* amount (- 1 (third entry))))) amount)))

(defmethod status-blow ((creature creature) (kind (eql :damage)) amount status)
  (burn creature (resisted creature (status-element status) amount)))

(defmethod status-blow ((creature creature) (kind (eql :heal)) amount status)
  (setf (health creature) (min (max-health creature) (+ (health creature) amount))))

(defmethod status-blow ((player player) (kind (eql :damage)) amount status)
  (hurt-player player amount (feet player) :shove NIL :by (status-caster status)))

(defmethod status-blow ((player player) (kind (eql :heal)) amount status)
  (setf (health player) (min *player-max-health* (+ (health player) amount))))

;;; Bursts (BURST-SPELL, spells.lisp).

(defun burst-victims (point radius caster)
  "The live bodies within RADIUS of POINT with nothing solid between, but CASTER and
those CASTER spares."
  (let ((victims ()))
    (loop for c across *creatures*
          for loc = (location c)
          when (and (not (dead c)) (not (eq c caster))
                    (not (and caster (spares-p caster c)))
                    (< (+ (expt (- (vx loc) (vx point)) 2) (expt (- (vz loc) (vz point)) 2))
                       (expt (+ radius (body-radius c)) 2))
                    (< (- (vy loc) radius) (vy point) (+ (vy loc) (sprite-height c) radius))
                    (clear-path-p point loc 0.0))
            do (push c victims))
    (when (and *player* (not (eq caster *player*)))
      (let ((feet (feet *player*)))
        (when (and (< (+ (expt (- (vx feet) (vx point)) 2) (expt (- (vz feet) (vz point)) 2))
                      (expt (+ radius *player-radius*) 2))
                   (< (- (vy feet) radius) (vy point) (+ (vy feet) *player-height* radius))
                   (clear-path-p point feet 0.0))
          (push *player* victims))))
    victims))

;;; Effects.

(defun element-rider (target element)
  "What ELEMENT does besides its damage to TARGET."
  (when (eq element :frost)
    (afflict target :slow *frost-chill* *frost-chill-time* :element :frost)))

(defmethod apply-effect ((kind (eql :damage)) effect (target creature) source)
  (let ((element (effect-element effect))
        (amount (roll (effect-magnitude effect))))
    (if (< 0 (effect-duration effect))
        (afflict target :damage amount (effect-duration effect) :element element :caster (caster source))
        ;; Blood sprays away from where it struck from.
        (hurt target (resisted target element amount)
              :from (effect-origin source)
              :pain-bonus (+ (spell-pain-bonus (spell source)) (if (eq element :shock) *shock-pain-bonus* 0))))
    (element-rider target element)))

;; A creature's spell, hitting the player: the shove goes the way its source pushes.
(defmethod apply-effect ((kind (eql :damage)) effect (target player) source)
  (let ((element (effect-element effect))
        (amount (roll (effect-magnitude effect))))
    (if (< 0 (effect-duration effect))
        (afflict target :damage amount (effect-duration effect) :element element :caster (caster source))
        (hurt-player target amount (effect-origin source)
                     :unblockable (effect-unblockable-p source) :by (caster source)))
    (element-rider target element)))

(defmethod apply-effect ((kind (eql :heal)) effect (target player) source)
  (let ((amount (roll (effect-magnitude effect))))
    (cond ((< 0 (effect-duration effect))
           (afflict target :heal amount (effect-duration effect) :caster target)
           (flash-resource target :health))
          (T
           (restore-resource target :health amount)))))

(defmethod apply-effect ((kind (eql :heal)) effect (target creature) source)
  (setf (health target) (min (max-health target) (+ (health target) (roll (effect-magnitude effect))))))

(defmethod apply-effect ((kind (eql :slow)) effect (target afflicted) source)
  (unless (and (typep target 'creature) (dead target))
    (afflict target :slow (roll (effect-magnitude effect)) (max 1 (effect-duration effect))
             :caster (caster source))))

(defmethod apply-effect ((kind (eql :ward)) effect (target player) source)
  (afflict target :ward (roll (effect-magnitude effect)) (max 1 (effect-duration effect)))
  (flash-resource target :ward))

(defmethod apply-effect ((kind (eql :drain)) effect (target creature) source)
  (unless (dead target)
    (let* ((before (max 0 (health target)))
           (amount (roll (effect-magnitude effect))))
      (hurt target amount :from (effect-origin source) :pain-bonus (spell-pain-bonus (spell source)))
      (let ((gain (round (* *drain-share* (min amount before))))
            (caster (caster source)))
        (when (and (typep caster 'player) (< 0 gain))
          (restore-resource caster :health gain))))))
