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
   (duration :initarg :duration :initform NIL :accessor status-duration
             :documentation "Seconds it lasts from when it was last put on or renewed, for the
HUD's time bar (status-icons.lisp); NIL until set, when LEFT stands in.")
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
  (let ((status (status-of actor kind))
        (duration (float duration 0f0)))
    (cond (status
           ;; Renewed for longer than it has left: its time bar fills again.
           (when (< (status-left status) duration)
             (setf (status-left status) duration
                   (status-duration status) duration))
           (setf (status-magnitude status) (max (status-magnitude status) magnitude))
           (when element
             (setf (status-element status) element))
           (when caster
             (setf (status-caster status) caster)))
          (T
           (push (make-instance 'status :kind kind :magnitude magnitude :left duration :duration duration
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
  "Tint CREATURE toward the element of a slow on it (a frost chill), if its hit flash is weaker.
Damage over time shows as its aura (STATUS-AURA) instead: a tint drowned a burning creature's flames."
  (let ((status (status-of creature :slow)))
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
  (burn creature (resisted creature (status-element status) amount) :by (status-caster status)))

(defmethod status-blow ((creature creature) (kind (eql :heal)) amount status)
  (setf (health creature) (min (max-health creature) (+ (health creature) amount))))

(defmethod status-blow ((player player) (kind (eql :damage)) amount status)
  (hurt-player player amount (feet player) :shove NIL :by (status-caster status)))

(defmethod status-blow ((player player) (kind (eql :heal)) amount status)
  (setf (health player) (min (max-health player) (+ (health player) amount))))

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
              :pain-bonus (+ (spell-pain-bonus (spell source)) (if (eq element :shock) *shock-pain-bonus* 0))
              :by (caster source)))
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
      (hurt target amount :from (effect-origin source) :pain-bonus (spell-pain-bonus (spell source))
                          :by (caster source))
      (let ((gain (round (* *drain-share* (min amount before))))
            (caster (caster source)))
        (when (and (typep caster 'player) (< 0 gain))
          (restore-resource caster :health gain))))))

;;; Auras: damage over time shows on a creature as its element on it (a STATUS-AURA, one per
;;; creature, in its STATUS-AURA slot): wisps of flame, snowflakes or crackling arcs, looping over
;;; and round its body while the status lasts, with a lamp for fire and shock; healing over time
;;; as green pluses rising off it (no creature heals itself so yet), in a slot of its own
;;; (HEAL-AURA), so a creature under both shows both.
;;; It is an effect sprite, fullbright and camera-facing, standing at the middle of the body and
;;; pulled toward the camera so it draws in front of the billboard. The creature's tick spawns
;;; and ends it (UPDATE-STATUS-AURA); a save leaves it out, and it comes back from the status.
;;; Strips: data/sprites/status, generated sheets (CLAUDE.md, "Monster sprites").

(define-fx-animation burn-aura "sprites/status/burn" :fps 10 :loop T)
(define-fx-animation frost-aura "sprites/status/frost" :fps 8 :loop T)
(define-fx-animation shock-aura "sprites/status/shock" :fps 14 :loop T)
(define-fx-animation regen-aura "sprites/status/regen" :fps 8 :loop T)

(defparameter *status-auras*
  '((:fire burn-aura 1.25 (1.6 0.75 0.3) 3.5 0.3)
    (:frost frost-aura 1.15 NIL 0 0)
    (:shock shock-aura 0.85 (0.9 0.9 1.4) 2.5 0.6)
    (:heal regen-aura 1.15 (0.2 0.55 0.18) 2.0 0.0))
  "(KEY ANIMATION SIZE LAMP-COLOR LAMP-RADIUS FLICKER) for each aura, keyed by a damage status's
element or :HEAL for healing over time (AURA-KEY): SIZE its height
against its creature's SPRITE-HEIGHT (drawn in proportion, wider than the body where it is more than
about 1, so flames and flakes dance round its outline: a red imp swallowed flames on it), and its
lamp, NIL for none.")
(defparameter *aura-rise* 0.45 "Where the aura's middle stands, up its creature's height.")
(defparameter *aura-pull* 0.35 "Metres the aura stands toward the camera from its creature's middle.")
(defparameter *heal-aura-pull* 0.3
  "The same for healing over time's: a little behind damage's, so the two never flicker where
they overlap.")

(define-shader-entity status-aura (fx-sprite)
  ((host :initarg :host :reader aura-host :documentation "The creature it burns on.")
   (element :initarg :element :reader aura-element)
   (size :initarg :size :initform 1.0 :reader aura-size)))

(defun aura-entry (element)
  (or (assoc element *status-auras*) (assoc :fire *status-auras*)))

(defun spawn-status-aura (creature element)
  (destructuring-bind (name size color radius flicker) (rest (aura-entry element))
    (let ((aura (make-instance 'status-aura :animation (find-fx-animation name) :host creature
                                            :element element :size size
                                            :location (vcopy (location creature)))))
      (enter aura (container creature))
      (when color
        (add-lamp (location aura) (apply #'vec color) radius :flicker flicker :source aura))
      aura)))

(defun aura-key (creature kind)
  "The aura CREATURE's status of KIND calls for: a damage over time's element, or :HEAL for
healing over time; NIL with no such status, or dead."
  (unless (dead creature)
    (let ((status (status-of creature kind)))
      (when (and status (< 0.0 (status-left status)))
        (if (eq kind :damage) (or (status-element status) :fire) :heal)))))

(defun sync-aura (creature aura wanted)
  "AURA, CREATURE's aura in one slot, made to show WANTED (an aura key, or NIL for none): ended
when it shows another or a reset took it from the scene, and spawned when there is none. The
aura the slot should hold now."
  (when (and aura (or (null (container aura)) (not (eq wanted (aura-element aura)))))
    (despawn aura)
    (setf aura NIL))
  (if (and wanted (null aura) (container creature))
      (spawn-status-aura creature wanted)
      aura))

(defun update-status-aura (creature)
  "Give CREATURE the auras its statuses call for while it lives, damage over time's and
healing over time's each in its own slot, and end each once its status or the creature is gone."
  (setf (status-aura creature) (sync-aura creature (status-aura creature) (aura-key creature :damage))
        (heal-aura creature) (sync-aura creature (heal-aura creature) (aura-key creature :heal))))

;; After FX-SPRITE's tick: stand on the host and face the camera, its size the host's.
(define-handler (status-aura tick :after) ()
  (let ((host (aura-host status-aura))
        (camera (camera (scene +main+))))
    (if (or (dead host) (null (container host)))
        (despawn status-aura)
        (let* ((at (location host))
               (loc (location status-aura))
               (height (float (sprite-height host) 0f0))
               (h (* (aura-size status-aura) height))
               (atlas (animation-atlas (sprite-animation status-aura)))
               (scale (scaling status-aura)))
          (setf (vx loc) (vx at)
                (vy loc) (+ (vy at) (* *aura-rise* height))
                (vz loc) (vz at)
                (vx scale) (* h (/ (getf atlas :cell-width) (float (getf atlas :cell-height) 0f0)))
                (vy scale) h)
          (when camera
            (let* ((eye (location camera))
                   (dx (- (vx eye) (vx loc)))
                   (dy (- (vy eye) (vy loc)))
                   (dz (- (vz eye) (vz loc)))
                   (d (sqrt (+ (* dx dx) (* dy dy) (* dz dz)))))
              (when (< 0.01 d)
                (let ((k (/ (min (if (eq :heal (aura-element status-aura)) *heal-aura-pull* *aura-pull*)
                                 (* 0.5 d))
                            d)))
                  (incf (vx loc) (* k dx))
                  (incf (vy loc) (* k dy))
                  (incf (vz loc) (* k dz))))))))))

(defun preload-status-auras (scene)
  "Load every aura's strip: they are spawned mid-game."
  (loop for (nil name) in *status-auras*
        do (preload (make-instance 'status-aura :animation (find-fx-animation name)) scene)))
