(in-package #:hexmaw)

;;; Pickups: things hovering in the level that the player takes by touching them. Herbs give
;;; health back at once and a shard mana; at full, one stays where it is. A potion goes into the
;;; inventory (inventory.lisp) instead, to be drunk later, unless there's no room for it.
;;; The blocks say where one may go (`pickup` in a blueprint, *PICKUP-SPOTS*), and each
;;; generated level puts as many in those spots as its monsters call for (PLACE-PICKUPS).
;;; A taken pickup stays in the scene, undrawn, so a reset only has to clear the flag.

;; The strips' cell heights, at the monsters' 64 px per metre.
(define-fx-animation pickup-herbs "sprites/pickups/herbs" :fps 5 :loop T :size (/ 32 64.0))
(define-fx-animation pickup-health-potion "sprites/pickups/flask" :fps 5 :loop T :size (/ 38 64.0))
(define-fx-animation pickup-shard "sprites/pickups/shard" :fps 5 :loop T :size (/ 28 64.0))
(define-fx-animation pickup-mana-potion "sprites/pickups/mana-potion" :fps 5 :loop T :size (/ 38 64.0))

(defparameter *pickup-kinds*
  '((:herbs :animation pickup-herbs :resource :health :amount 15)
    (:health-potion :animation pickup-health-potion :item :health-potion :resource :health :amount 40)
    (:shard :animation pickup-shard :resource :mana :amount 28)
    (:mana-potion :animation pickup-mana-potion :item :mana-potion :resource :mana :amount 50))
  "What each kind of pickup restores, and how much, at once or as the :ITEM it gives (keep :AMOUNT
the item's, *ITEM-KINDS*: a level's budget counts it).")

(defparameter *pickup-hover* 0.15 "Metres from the floor to the bottom of a pickup.")
(defparameter *pickup-bob* 0.04 "Metres a pickup bobs up and down from its height.")
(defparameter *pickup-bob-rate* 2.5 "Radians per second of the bob.")
(defparameter *pickup-reach* 0.9 "Metres across from the player's centre at which a pickup is touched.")
(defparameter *pickup-below* 0.4
  "How far under the floor a pickup stands on the player's feet may be and still touch it: a
step's height, so one on a 0.8 m sarcophagus takes a jump.")
(defparameter *pickup-above* 0.8
  "How far over that floor the player's feet may be: the top of the pickup, about.")

(defparameter *health-per-monster* 10 "Health a generated level's pickups restore, per monster in it.")
(defparameter *mana-per-monster* 15 "Mana a generated level's pickups restore, per monster in it.")
(defparameter *pickup-potion-every* 2 "Every so many pickups of a resource, one is a potion, on a reward spot if one is free.")
(defparameter *pickup-room-weight* 2 "How much likelier a spot in a room is than one in a corridor.")
(defparameter *jump-reach* 1.0 "Metres above a floor the player can jump to get onto: a reward spot's limit.")

(defun pickup-property (kind key)
  (getf (rest (or (assoc kind *pickup-kinds*) (error "No pickup kind ~s." kind))) key))

(defvar *pickups* (make-array 0 :adjustable T :fill-pointer T)
  "Every pickup in the level, taken or not, in the order they were placed: a save names the
taken ones by their place here. BUILD-LEVEL empties it. Past *BUILT-PICKUPS* are those
dropped in play (DROP-LOOT).")

(defvar *built-pickups* 0
  "How many of *PICKUPS* the level was built with; the rest were dropped in play, by thieving
imps (imp.lisp), and a save keeps them apart.")

(define-shader-entity pickup (upright-fx)
  ((kind :initarg :kind :reader pickup-kind)
   (ground :initarg :ground :reader pickup-ground :documentation "Height of the floor it stands on.")
   (taken :initform NIL :accessor taken)))

(defun add-pickup (container kind x y z &key (phase 0.0))
  "A pickup of KIND standing on the floor at X Y Z. PHASE is seconds into its glint and bob."
  (let* ((animation (find-fx-animation (pickup-property kind :animation)))
         (pickup (make-instance 'pickup :animation animation :kind kind :ground (float y 0f0)
                                        :location (vec x (+ y *pickup-hover* (* 0.5 (animation-size animation))) z))))
    (setf (age pickup) phase)
    (vector-push-extend pickup *pickups*)
    (enter pickup container)
    pickup))

(defgeneric collect-pickup (pickup player)
  (:documentation "Give PICKUP to PLAYER. True if it was used up, NIL if it stays where it is."))

(defun flash-resource (player resource)
  "Flash the view in RESOURCE's colour (RESTORE-FLASH, hud.lisp)."
  (setf (restore-flash player) *restore-flash-time*
        (restored player) resource))

(defun restore-resource (player resource amount)
  "Give PLAYER AMOUNT of RESOURCE, :HEALTH or :MANA, and flash the view. NIL if it was full."
  (when (ecase resource
          (:health (when (< (health player) *player-max-health*)
                     (setf (health player) (min *player-max-health* (+ (health player) amount)))))
          (:mana (when (< (mana player) *max-mana*)
                   (setf (mana player) (min *max-mana* (+ (mana player) amount))))))
    (flash-resource player resource)
    T))

(defmethod collect-pickup ((pickup pickup) player)
  (let* ((kind (pickup-kind pickup))
         (resource (pickup-property kind :resource))
         (item (pickup-property kind :item)))
    (if item
        (when (give-item player item)
          (flash-resource player resource)
          T)
        (restore-resource player resource (pickup-property kind :amount)))))

(defun touching-pickup-p (pickup player)
  (let* ((feet (feet player))
         (at (location pickup))
         (dx (- (vx at) (vx feet)))
         (dz (- (vz at) (vz feet)))
         (dy (- (vy feet) (pickup-ground pickup))))
    (and (< (+ (* dx dx) (* dz dz)) (* *pickup-reach* *pickup-reach*))
         (< (- *pickup-below*) dy *pickup-above*))))

(define-handler (pickup tick :after) ()
  (unless (or (taken pickup) (frozen-p))
    (setf (vy (location pickup))
          (+ (pickup-ground pickup) *pickup-hover* (* 0.5 (animation-size (sprite-animation pickup)))
             (* *pickup-bob* (sin (* *pickup-bob-rate* (age pickup))))))
    (when (and *player* (< 0 (health *player*)) (touching-pickup-p pickup *player*)
               (collect-pickup pickup *player*))
      (setf (taken pickup) T))))

(defmethod render :around ((pickup pickup) (program shader-program))
  (unless (taken pickup)
    (call-next-method)))

(defun restore-pickups ()
  "Every pickup back in its place, for a new run, and those dropped in play gone."
  (loop for i from *built-pickups* below (length *pickups*)
        do (despawn (aref *pickups* i)))
  (setf (fill-pointer *pickups*) (min *built-pickups* (length *pickups*)))
  (loop for pickup across *pickups* do (setf (taken pickup) NIL)))

(defun taken-pickup-indices ()
  (loop for pickup across *pickups*
        for i from 0 below *built-pickups*
        when (taken pickup) collect i))

(defun dropped-pickups ()
  "The pickups dropped in play and not taken again, as a save keeps them: kind and place."
  (loop for i from *built-pickups* below (length *pickups*)
        for pickup = (aref *pickups* i)
        unless (taken pickup)
          collect (let ((at (location pickup)))
                    (list (pickup-kind pickup) (vx at) (pickup-ground pickup) (vz at)))))

(defun restore-dropped-pickups (container drops)
  (loop for (kind x y z) in drops
        do (add-pickup container kind x y z)))

;;; Loot: what a thieving imp (imp.lisp) carries off, held over its head, and drops where it
;;; dies. The pickup it took stays taken; what it drops is a new one.

(defun item-pickup-kind (item)
  "The kind of pickup that gives ITEM, an item kind (*ITEM-KINDS*)."
  (or (first (find item *pickup-kinds* :key (lambda (entry) (getf (rest entry) :item))))
      item))

(defun loose-pickup-near (point range)
  "The nearest pickup not taken within RANGE metres of POINT, on its storey, or NIL."
  (let ((best NIL) (best-d (* range range)))
    (loop for pickup across *pickups*
          for at = (location pickup)
          for d = (+ (expt (- (vx at) (vx point)) 2) (expt (- (vz at) (vz point)) 2))
          when (and (not (taken pickup)) (< d best-d)
                    (< (abs (- (pickup-ground pickup) (vy point))) 1.5))
            do (setf best pickup best-d d))
    best))

(defun drop-loot (container kind x y z)
  "Drop a pickup of KIND on the floor at X Y Z, past those the level was built with."
  (add-pickup container kind x y z))

(defparameter *loot-lift* 0.05 "Metres over its carrier's head that loot is held.")
(defparameter *loot-scale* 0.6 "Size loot is drawn at, against the pickup's: held up, it looks nearer.")

(define-shader-entity carried-loot (upright-fx)
  ((carrier :initarg :carrier :reader carrier)))

(defmethod initialize-instance :after ((loot carried-loot) &key)
  (let ((scale (scaling loot)))
    (setf (vx scale) (* (vx scale) *loot-scale*)
          (vy scale) (* (vy scale) *loot-scale*))))

(defun add-carried-loot (carrier kind)
  "Show a pickup of KIND held over CARRIER's head until it no longer carries it."
  (let ((loot (make-instance 'carried-loot :animation (find-fx-animation (pickup-property kind :animation))
                                           :carrier carrier :location (vcopy (location carrier)))))
    (enter loot (container carrier))
    loot))

(define-handler (carried-loot tick :after) ()
  (let ((carrier (carrier carried-loot)))
    (if (or (dead carrier) (null (stolen carrier)) (null (container carrier)))
        (despawn carried-loot)
        (let ((loc (location carrier))
              (at (location carried-loot)))
          (setf (vx at) (vx loc)
                (vy at) (+ (vy loc) (sprite-height carrier) *loot-lift* (* 0.5 (vy (scaling carried-loot))))
                (vz at) (vz loc))))))

(defun preload-pickups (scene)
  "Pickups are dropped and carried off in play: load every kind's sprite up front."
  (loop for (kind . properties) in *pickup-kinds*
        for animation = (find-fx-animation (getf properties :animation))
        do (preload (make-instance 'pickup :animation animation :kind kind :ground 0.0) scene)
           (preload (make-instance 'carried-loot :animation animation :carrier NIL) scene)))

(defun take-pickups-at (indices)
  (dolist (i indices)
    (when (< i (length *pickups*))
      (setf (taken (aref *pickups* i)) T))))

;;; Where they go.

(defun spot-reached-p (spot seen)
  "True if the player, who can walk to the cells SEEN (NAV-REACHED), can get to SPOT. A floor
spot's own cell must be one of them. A reward spot's may instead be up to *JUMP-REACH* above
one of them, within 2 m across: a jump onto what it stands on."
  (let* ((p (getf spot :position))
         (r *player-radius*) (h *player-height*)
         (y (+ (vy p) 0.1)))
    (or (multiple-value-bind (i j k) (nav-nearest-fitting (vec (vx p) y (vz p)) r h :search 1 :reach 0.5)
          (and i (= 1 (sbit seen (nav-index i j k)))))
        (and (eq :reward (getf spot :tier))
             (multiple-value-bind (ci cj) (nav-cell (vx p) (vz p))
               (and ci
                    (loop for i from (- ci 4) to (+ ci 4)
                          thereis (loop for j from (- cj 4) to (+ cj 4)
                                        thereis (loop for k from 0 below (nav-layers *nav-grid*)
                                                      thereis (and (nav-fits-p i j k r h)
                                                                   (<= (- (vy p) *jump-reach*) (nav-floor i j k) (vy p))
                                                                   (= 1 (sbit seen (nav-index i j k)))))))))))))

(defun pick-spot (spots tiers used random &key fresh)
  "One of SPOTS at random, of the first of TIERS with any in a block not in USED, a room's
*PICKUP-ROOM-WEIGHT* times as likely as a corridor's; failing those, unless FRESH, of the first
with any at all. NIL if there are none."
  (flet ((pick (candidates)
           (flet ((weight (spot)
                    (if (member :room (block-tags (map-block-name (getf spot :block))))
                        *pickup-room-weight*
                        1)))
             (let ((roll (random (reduce #'+ candidates :key #'weight) random)))
               (dolist (spot candidates)
                 (decf roll (weight spot))
                 (when (< roll 0) (return spot)))))))
    (flet ((try (keep)
             (dolist (tier tiers)
               (let ((candidates (remove-if-not (lambda (spot) (and (eq tier (getf spot :tier)) (funcall keep spot)))
                                                spots)))
                 (when candidates (return (pick candidates)))))))
      (or (try (lambda (spot) (not (member (getf spot :block) used))))
          (and (not fresh) (try (constantly T)))))))

(defun scatter-pickups (container)
  "Fill a generated level's spots until its pickups restore what its monsters call for. Drawn
from a random state of their own, so the level and its monsters don't change."
  (let* ((random (sb-ext:seed-random-state *last-level-seed*))
         (*nav-hazards* :swim)
         (seen (multiple-value-bind (i j k) (nav-nearest-fitting *spawn-point* *player-radius* *player-height*)
                 (and i (nav-reached i j k *player-radius* *player-height* *step-height*))))
         ;; The player starts full, so nothing goes in the first room.
         (start (map-block-at (vx *spawn-point*) (+ (vy *spawn-point*) 0.1) (vz *spawn-point*)))
         (spots (when seen
                  (loop for spot across *pickup-spots*
                        when (and (not (eq start (getf spot :block))) (spot-reached-p spot seen))
                          collect spot)))
         (monsters (length *creatures*))
         (health-owed (* monsters *health-per-monster*))
         (mana-owed (* monsters *mana-per-monster*))
         (health-count 0) (mana-count 0)
         (used ()))
    (flet ((place (health-p)
             ;; True if there was somewhere to put it.
             (let* ((potion (= (1- *pickup-potion-every*)
                               (mod (if health-p health-count mana-count) *pickup-potion-every*)))
                    ;; A reward spot, but never at the cost of a block with two while another has none.
                    (spot (or (and potion (pick-spot spots '(:reward) used random :fresh T))
                              (pick-spot spots '(:floor :reward) used random))))
               (when spot
                 (let ((kind (if health-p
                                 (if potion :health-potion :herbs)
                                 (if potion :mana-potion :shard)))
                       (p (getf spot :position)))
                   (add-pickup container kind (vx p) (vy p) (vz p) :phase (random 10.0 random))
                   (setf spots (remove spot spots))
                   (push (getf spot :block) used)
                   (if health-p
                       (progn (incf health-count) (decf health-owed (pickup-property kind :amount)))
                       (progn (incf mana-count) (decf mana-owed (pickup-property kind :amount)))))
                 T))))
      ;; Whichever resource still owes the larger part of its budget goes next.
      (loop while (or (< 0 health-owed) (< 0 mana-owed))
            while (place (< (/ mana-owed (max 1 *mana-per-monster*)) (/ health-owed (max 1 *health-per-monster*))))))
    (v:info :hexmaw "~d pickups for ~d monsters: ~d health, ~d mana~@[, ~d health and ~d mana short~]."
            (length *pickups*) monsters health-count mana-count
            (when (or (< 0 health-owed) (< 0 mana-owed)) (max 0 health-owed))
            (max 0 mana-owed))))

(defun fill-pickup-spots (container)
  "A pickup on every spot, alternating health and mana, to look them over in the gallery."
  (loop for spot across *pickup-spots*
        for p = (getf spot :position)
        for health-p = T then (not health-p)
        do (add-pickup container
                       (if (eq :reward (getf spot :tier))
                           (if health-p :health-potion :mana-potion)
                           (if health-p :herbs :shard))
                       (vx p) (vy p) (vz p))))

(defun place-pickups (container)
  "Put the level's pickups in. Last in BUILD-LEVEL: it asks the nav grid who can reach what."
  (case *level*
    (:generated (scatter-pickups container))
    (:gallery (fill-pickup-spots container))))
